/*
Copyright 2017-2019 VMware, Inc.
SPDX-License-Identifier: BSD-2-Clause
*/
package com.vmware.weathervane.auction.data.model;

import java.io.Serializable;
import java.text.DateFormat;
import java.util.Date;
import java.util.HashSet;
import java.util.Set;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.FetchType;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.JoinTable;
import javax.persistence.ManyToMany;
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.Table;
import javax.persistence.Temporal;
import javax.persistence.TemporalType;
import javax.persistence.Version;

@Entity
@Table(name="auction")
//@Cacheable
//@Cache(usage=CacheConcurrencyStrategy.READ_WRITE)
public class Auction implements Serializable, DomainObject {

	private static final long serialVersionUID = 1L;

	public enum AuctionState {
		FUTURE, PENDING, RUNNING, COMPLETE, INVALID, NOSUCHAUCTION
	};

	private Long id;
	private AuctionState state;
	private String name;
	private String category;
	private Date startTime;
	private Date endTime;

	// References to other entities
	private User auctioneer;

	private Set<Item> items = new HashSet<Item>();
	private Set<Keyword> keywords = new HashSet<Keyword>();
	
	private Integer version;

	/*
	 * These flags exists to provide information that simplifies
	 * preloading and preparing benchmark runs.  It is not used by 
	 * the Auction application
	 */
	private boolean current;
	private boolean activated;
	
	public Auction() {

	}

	@Id
	@GeneratedValue(strategy=GenerationType.TABLE)
	public Long getId() {
		return id;
	}

	private void setId(Long id) {
		this.id = id;
	}

	@Enumerated(EnumType.STRING)
	public AuctionState getState() {
		return state;
	}

	public void setState(AuctionState state) {
		this.state = state;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public String getCategory() {
		return category;
	}

	public void setCategory(String category) {
		this.category = category;
	}

	@Temporal(TemporalType.TIMESTAMP)
	@Column(name="starttime")
	public Date getStartTime() {
		return startTime;
	}

	public void setStartTime(Date startTime) {
		this.startTime = startTime;
	}

	@Temporal(TemporalType.TIMESTAMP)
	@Column(name="endtime")
	public Date getEndTime() {
		return endTime;
	}

	public void setEndTime(Date endTime) {
		this.endTime = endTime;
	}

	@OneToMany(mappedBy = "auction", cascade = { CascadeType.PERSIST })
	public Set<Item> getItems() {
		return items;
	}

	public void setItems(Set<Item> items) {
		this.items = items;
	}

	@ManyToMany
	@JoinTable(name="auction_keyword",
				joinColumns={@JoinColumn(name="auction_id", referencedColumnName="id")},
				inverseJoinColumns={@JoinColumn(name="keyword_id", referencedColumnName="id")})
	public Set<Keyword> getKeywords() {
		return keywords;
	}

	private void setKeywords(Set<Keyword> keywords) {
		this.keywords = keywords;
	}
	
	public void addKeyword(Keyword keyword) {
		this.keywords.add(keyword);
	}

	@ManyToOne(fetch=FetchType.LAZY)
	@JoinColumn(name="auctioneer_id",referencedColumnName="id")
	public User getAuctioneer() {
		return auctioneer;
	}

	public void setAuctioneer(User auctioneer) {
		this.auctioneer = auctioneer;
	}

	@Version
	public Integer getVersion() {
		return version;
	}

	public void setVersion(Integer version) {
		this.version = version;
	}

	public boolean addItemToAuction(Item item) {
		item.setAuction(this);
		return this.getItems().add(item);
	}

	public boolean isCurrent() {
		return current;
	}

	public void setCurrent(boolean current) {
		this.current = current;
	}

	public boolean isActivated() {
		return activated;
	}

	public void setActivated(boolean activated) {
		this.activated = activated;
	}

	@Override
	public String toString() {
		String theString = "Auction name: " + name + " : Auction State: " + state
				+ " : Id: " + id + " : Category: " + category.toString()
				+ " : Start Time: " + DateFormat.getDateTimeInstance().format(startTime);

		return theString;
	}
	
}
