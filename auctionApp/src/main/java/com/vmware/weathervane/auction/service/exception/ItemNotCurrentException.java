/*
Copyright 2017-2019 VMware, Inc.
SPDX-License-Identifier: BSD-2-Clause
*/
/**
 * 
 *
 * @author Hal
 */
package com.vmware.weathervane.auction.service.exception;

/**
 * @author Hal
 *
 */
public class ItemNotCurrentException extends LiveAuctionServiceException {

	public ItemNotCurrentException() {
		super();
	}
	
	public ItemNotCurrentException(String msg) {
		super(msg);
	}

}
