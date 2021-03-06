# Copyright 2017-2019 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
package AuctionKubernetesAppInstance;

use Moose;
use MooseX::Storage;
use MooseX::ClassAttribute;
use POSIX;
use Tie::IxHash;
use Log::Log4perl qw(get_logger);
use AppInstance::AuctionAppInstance;
use ComputeResources::Cluster;

with Storage( 'format' => 'JSON', 'io' => 'File' );

use namespace::autoclean;

use WeathervaneTypes;

extends 'AuctionAppInstance';

has 'namespace' => (
	is  => 'rw',
	isa => 'Str',
);

has 'imagePullPolicy' => (
	is      => 'rw',
	isa     => 'Str',
	default => "IfNotPresent",
);

override 'initialize' => sub {
	my ($self) = @_;
	
	$self->namespace("auctionw" . $self->workload->instanceNum . "i" . $self->instanceNum);

	if ($self->getParamValue('redeploy')) {
	    $self->imagePullPolicy('Always');
	}
	
	super();

};

override 'getDeployedConfiguration' => sub {
	my ( $self, $destinationPath) = @_;
	
	# Get a host from the first appServer (since there will always be an appServer)
	my $appServersRef = $self->getAllServicesByType("appServer");
	my $anAppServer = $appServersRef->[0];	
	my $cluster = $anAppServer->host;
	
	# Get the pod configuration and save it to a file
	open( FILEOUT, ">$destinationPath/" . $self->namespace . "-GetAll.txt" ) or die "Can't open file $destinationPath/" . $self->namespace . "-GetAll.txt: $!\n";	
	my $out = $cluster->kubernetesGetAll($self->namespace);
	my @out = split /\n/, $out;
	for my $line (@out) {
		print FILEOUT "$line\n";
	}
	close FILEOUT;
};

override 'startServices' => sub {
	my ( $self, $serviceTier, $setupLogDir, $forked ) = @_;
	my $logger = get_logger("Weathervane::AppInstance::AuctionKubernetesAppInstance");
	my $users  = $self->dataManager->getParamValue('maxUsers');
	my $impl         = $self->getParamValue('workloadImpl');

	my $appInstanceName = $self->name;
	my $logName         = "$setupLogDir/start-$serviceTier-$appInstanceName.log";
	my $logFile;
	open( $logFile, " > $logName " ) or die " Error opening $logName: $!";

	my $namespace = $self->namespace;
	my $cluster = $self->host;
	# Create the namespace and the namespace-wide resources
	$cluster->kubernetesCreateNamespace($namespace);
	
	$logger->debug(
		"startServices for serviceTier $serviceTier, workload ",
		$self->workload->instanceNum,
		", appInstance ",
		$self->instanceNum,
		", impl = $impl", 
		" users = $users",
		" setupLogDir = $setupLogDir"
	);

	my $serviceTiersHashRef = $WeathervaneTypes::workloadToServiceTypes{$impl};
	my $serviceTypes = $serviceTiersHashRef->{$serviceTier};
	if ($serviceTypes) {
		$logger->debug("startServices for serviceTier $serviceTier, serviceTypes = @$serviceTypes");
		foreach my $serviceType (@$serviceTypes) {
			my $servicesRef = $self->getAllServicesByType($serviceType);
			if ($#{$servicesRef} >= 0) {
				# Use the first instance of the service for starting the 
				# service instances
				my $serviceRef = $servicesRef->[0];
				$serviceRef->start($serviceType, $users, $setupLogDir);
			} else {
				next;
			}		
		}
		
		# Don't return until all services are ready
		my $allIsRunningAndUp = $self->isRunningAndUpServices($serviceTier, $logFile, $forked);
		if ( !$allIsRunningAndUp ) {
			close $logFile;
			return 0;
		}
	}
	close $logFile;
	return 1;
};

override 'cleanup' => sub {
	my ( $self, $cleanupLogDir ) = @_;
	my $logger = get_logger("Weathervane::AppInstance::AuctionKubernetesAppInstance");
	
	my $cluster = $self->host;
	$cluster->kubernetesDeleteAllWithLabel("type=appInstance", $self->namespace);
	$cluster->kubernetesDeleteAllWithLabelAndResourceType("type=appInstance", "ingress", $self->namespace);
	
};

override 'getEdgeAddrsRef' => sub {
	my ($self) = @_;
	my $cluster = $self->host;
	my $logger = get_logger("Weathervane::AppInstance::AuctionKubernetesAppInstance");
	
	my $wwwIpAddrsRef = [];
	
	$logger->debug("getEdgeAddrsRef: useLoadBalancer = " . $cluster->getParamValue('useLoadBalancer'));
	if ($cluster->getParamValue('useLoadBalancer')) {
	  	my ($cmdFailed, $ip) = $cluster->kubernetesGetLbIP("nginx", $self->namespace);
		if ($cmdFailed)	{
			$logger->error("Error getting IP for frontend loadbalancer: error = $cmdFailed");
	  	} else {
			push @$wwwIpAddrsRef, [$ip, 80, 443];
	  	}							
	} else {
		# Using NodePort service for ingress
		# Get the IP addresses of the nginx-ingress in this appInstance's namespace
		my $ipAddrsRef = $cluster->kubernetesGetNodeIPs();
		if ($#{$ipAddrsRef} < 0) {
			$logger->error("There are no IP addresses for the Kubernetes nodes");
			exit 1;
		}
	
		my $httpPort = $cluster->kubernetesGetNodePortForPortNumber("app=auction,type=webServer", 80, $self->namespace);
		my $httpsPort = $cluster->kubernetesGetNodePortForPortNumber("app=auction,type=webServer", 443, $self->namespace);
	
		foreach my $ipAddr (@$ipAddrsRef) {
			push @$wwwIpAddrsRef, [$ipAddr, $httpPort, $httpsPort];							
		}
	}
	return $wwwIpAddrsRef;
};

override 'getServiceConfigParameters' => sub {
	my ( $self, $service, $serviceType ) = @_;
	my %serviceParameters = ();

	my $users = $self->getParamValue('maxUsers');

	if ( ($serviceType eq "appServer") || ($serviceType eq 'auctionBidServer') ) {

		# For the app Servers, Auction needs to provide JVM options
		my $jvmOpts = "";

		# This variable is a holder for all spring profiles that are active
		my $springProfilesActive = $self->getSpringProfilesActive();
		$jvmOpts .= " -Dspring.profiles.active=$springProfilesActive ";

		# Determine the sizes for the various application caches
		# if the number of auctions wasn't explicitly set, determine based on
		# the usersPerAuctionScaleFactor
		my $auctions = $self->getParamValue('auctions');
		if ( !$auctions ) {
			$auctions = ceil( $users / $self->getParamValue('usersPerAuctionScaleFactor') );
		}
		my $numAppServers                  = $self->getTotalNumOfServiceType('appServer');
		my $numWebServers                  = $self->getTotalNumOfServiceType('webServer');
		my $authTokenCacheSize             = 2 * $users;
		my $activeAuctionCacheSize         = 2 * $auctions;
		my $itemsForAuctionCacheSize       = 2 * $auctions;
		my $itemCacheSize                  = 20 * $auctions;
		my $auctionRepresentationCacheSize = 2 * $auctions;
		my $imageInfoCacheSize             = 100 * $auctions;

		my $itemThumbnailImageCacheSize =
		  $self->getParamValue('appServerThumbnailImageCacheSizeMultiplier') * $auctions;
		my $itemPreviewImageCacheSize = $self->getParamValue('appServerPreviewImageCacheSizeMultiplier') * $auctions;
		my $itemFullImageCacheSize    = $self->getParamValue('appServerFullImageCacheSizeMultiplier') * $auctions;
		$jvmOpts .= " -DAUTHTOKENCACHESIZE=$authTokenCacheSize -DACTIVEAUCTIONCACHESIZE=$activeAuctionCacheSize ";
		$jvmOpts .= " -DAUCTIONREPRESENTATIONCACHESIZE=$auctionRepresentationCacheSize ";
		$jvmOpts .= " -DIMAGEINFOCACHESIZE=$imageInfoCacheSize -DITEMSFORAUCTIONCACHESIZE=$itemsForAuctionCacheSize ";
		$jvmOpts .= " -DITEMCACHESIZE=$itemCacheSize ";


		my $zookeeperConnectionString = "";
		my $numCoordinationServers   = $self->getTotalNumOfServiceType('coordinationServer');
		for (my $i = 0; $i < $numCoordinationServers; $i++) {
			$zookeeperConnectionString .= "zookeeper-${i}.zookeeper:2181,";
		}
		chop $zookeeperConnectionString;
		$jvmOpts .= " -DZOOKEEPERCONNECTIONSTRING=$zookeeperConnectionString ";

		if ( $numWebServers > 1 ) {

			# Don't need to cache images in app server if there is a web
			# server since the web server caches.
			$itemThumbnailImageCacheSize = $auctions;
			$itemPreviewImageCacheSize   = 1;
			$itemFullImageCacheSize      = 1;
		}
		else {
			if ( $itemPreviewImageCacheSize == 0 ) {
				$itemPreviewImageCacheSize = 1;
			}

			if ( $itemFullImageCacheSize == 0 ) {
				$itemFullImageCacheSize = 1;
			}
		}
		$jvmOpts .= " -DITEMTHUMBNAILIMAGECACHESIZE=$itemThumbnailImageCacheSize ";
		$jvmOpts .= " -DITEMPREVIEWIMAGECACHESIZE=$itemPreviewImageCacheSize ";
		$jvmOpts .= " -DITEMFULLIMAGECACHESIZE=$itemFullImageCacheSize ";
		
		my $numCpus = $service->getParamValue("${serviceType}Cpus");
		my $highBidQueueConcurrency = $service->getParamValue('highBidQueueConcurrency');
		if (!$highBidQueueConcurrency) {
			$highBidQueueConcurrency = $numCpus;
		}
		$jvmOpts .= " -DHIGHBIDQUEUECONCURRENCY=$highBidQueueConcurrency ";

		if ( $service->getParamValue('randomizeImages') ) {
			$jvmOpts .= " -DRANDOMIZEIMAGES=true ";
		}
		else {
			$jvmOpts .= " -DRANDOMIZEIMAGES=false ";
		}
		
		my $newBidQueueConcurrency = $service->getParamValue('newBidQueueConcurrency');
		if (!$newBidQueueConcurrency) {
			$newBidQueueConcurrency = $numCpus;
		}		
		$jvmOpts .= " -DNEWBIDQUEUECONCURRENCY=$newBidQueueConcurrency ";

		# Turn on imageWriters in the application
		if ( $service->getParamValue('useImageWriterThreads') ) {
			if ( $service->getParamValue('imageWriterThreads') ) {
	
				# value was set, overriding the default
				$jvmOpts .= " -DIMAGEWRITERTHREADS=" . $service->getParamValue('imageWriterThreads') . " ";
			}
			else {

				my $iwThreads = floor( $numCpus / 2.0 );
				if ( $iwThreads < 1 ) {
					$iwThreads = 1;
				}
				$jvmOpts .= " -DIMAGEWRITERTHREADS=" . $iwThreads . " ";

			}

			$jvmOpts .= " -DUSEIMAGEWRITERTHREADS=true ";
		}
		else {
			$jvmOpts .= " -DUSEIMAGEWRITERTHREADS=false ";
		}
			
		$jvmOpts .= " -DNUMAUCTIONEERTHREADS=" . $service->getParamValue('numAuctioneerThreads') . " ";
			
		
		$jvmOpts .= " -DNUMCLIENTUPDATETHREADS=" . $service->getParamValue('numClientUpdateThreads') . " ";

		$jvmOpts .= " -DRABBITMQ_HOST=rabbitmq -DRABBITMQ_PORT=5672 ";

		$jvmOpts .= " -DCASSANDRA_CONTACTPOINTS=cassandra -DCASSANDRA_PORT=9042 ";

		$jvmOpts .= " -DDBHOSTNAME=postgresql -DDBPORT=5432 ";

		if ( !( $jvmOpts =~ /CompileThreshold/ ) ) {
			$jvmOpts .= " -XX:CompileThreshold=2000 ";
		}

		$serviceParameters{"jvmOpts"} = $jvmOpts;
	}

	return \%serviceParameters;
};

override 'redeploy' => sub {
	my ( $self, $logfile ) = @_;
};

override 'getHostStatsSummary' => sub {
	my ( $self, $csvRef, $statsLogPath, $filePrefix, $prefix ) = @_;
	
};

override 'startStatsCollection' => sub {
	my ( $self, $tmpDir ) = @_;
	#overrides AppInstance startStatsCollection calls for all services
};

override 'stopStatsCollection' => sub {
	my ( $self ) = @_;
	#overrides AppInstance stopStatsCollection calls for all services
};

override 'getStatsFiles' => sub {
	my ( $self ) = @_;

};

override 'cleanStatsFiles' => sub {
	my ( $self ) = @_;

};

override 'getLogFiles' => sub {
	my ( $self, $baseDestinationPath, $usePrefix ) = @_;
	my $logger = get_logger("Weathervane::AppInstance::AuctionKubernetesAppInstance");
	$logger->debug(
		"getLogFiles for workload ", $self->workload->instanceNum,
		", appInstance ",            $self->instanceNum
	);

	my $pid;
	my @pids;

	my $newBaseDestinationPath = $baseDestinationPath;
	if ($usePrefix) {
		$newBaseDestinationPath .= "/appInstance" . $self->instanceNum;
	}

	#  collection on services
	my $impl         = $self->getParamValue('workloadImpl');
	my $serviceTypes = $WeathervaneTypes::serviceTypes{$impl};
	foreach my $serviceType (@$serviceTypes) {
		my $servicesRef = $self->getAllServicesByType($serviceType);
		if ($#{$servicesRef} >= 0) {
			my $service = $servicesRef->[0];
			my $name = $service->host->name;
			my $destinationPath = $newBaseDestinationPath . "/" . $serviceType . "/" . $name;
			if ( !( -e $destinationPath ) ) {
				`mkdir -p $destinationPath`;
			}
			$service->getLogFiles($destinationPath);
		}
	}	
};

__PACKAGE__->meta->make_immutable;

1;
