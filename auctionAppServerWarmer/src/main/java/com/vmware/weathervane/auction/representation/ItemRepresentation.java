/*
Copyright 2017-2019 VMware, Inc.
SPDX-License-Identifier: BSD-2-Clause
*/
package com.vmware.weathervane.auction.representation;

import java.io.Serializable;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.vmware.weathervane.auction.imageStore.model.ImageInfo;
import com.vmware.weathervane.auction.model.Condition;
import com.vmware.weathervane.auction.model.HighBid;
import com.vmware.weathervane.auction.model.Item;
import com.vmware.weathervane.auction.model.Item.ItemState;

public class ItemRepresentation extends Representation implements Serializable {

	private static final long serialVersionUID = 1L;

	private static String ReadItemPath = "item/{itemId}";
	private static String UpdateItemPath = "item/{itemId}";

	private Long id;
	private String name;
	private String manufacturer;
	private Long auctionId;

	private Item.ItemState state;
	private Date biddingEndTime;
	private Float purchasePrice;

	private String longDescription;
	private Float startingBidAmount;
	private Condition condition;
	private Date dateOfOrigin;
	private Integer bidCount;
	
	// Only create an itemRepresentation with the factory method that
	// understands the business rules.
	private ItemRepresentation() {
	}


	public ItemRepresentation(Long itemId) {
			this.id = itemId;
			this.state = ItemState.NOSUCHITEM;
	}	
	
	private void intializeItemRepresentation(Item theItem) {
		
		this.setId(theItem.getId());
		if (theItem.getAuction() == null) {
			this.setAuctionId(null);
		} else {
			this.setAuctionId(theItem.getAuction().getId());
		}
		this.setName(theItem.getShortDescription());
		this.setManufacturer(theItem.getManufacturer());
		this.setLongDescription(theItem.getLongDescription());
		this.setCondition(theItem.getCondition());
		this.setDateOfOrigin(theItem.getDateOfOrigin());
		this.setStartingBidAmount(theItem.getStartingBidAmount());

		if (((theItem.getState() == ItemState.SOLD) || (theItem.getState() == ItemState.SHIPPED) || (theItem
				.getState() == ItemState.PAID)) && (theItem.getHighbid() != null)) {
			this.setPurchasePrice(theItem.getHighbid().getAmount());
		}
		
		HighBid highBid = theItem.getHighbid();
		if (highBid != null) {
			if (highBid.getBiddingEndTime() != null) {
				this.setBiddingEndTime(highBid.getBiddingEndTime());
			}
		}
		
		this.setState(theItem.getState());

		/*
		 * Add the links for the item and for the itemImages
		 */
		addLinksForEntity(Item.class.getSimpleName(), ItemRepresentation.createItemLinks(theItem));
	}

	public ItemRepresentation(Item theItem) {
		if (theItem == null) {
			this.setState(ItemState.NOSUCHITEM);
			return;
		}

		intializeItemRepresentation(theItem);
	
	}

	/**
	 * This constructor creates an itemRepresentation from an Item. It uses the
	 * business rules to determine what the allowable next actions are based on
	 * the current state of the auction and item. It then includes appropriate
	 * links for those actions in the representation.
	 * 
	 * @author hrosenbe
	 */
	public ItemRepresentation(Item theItem, List<ImageInfo> imagesInfo, boolean cacheable) {

		if (theItem == null) {
			this.setState(ItemState.NOSUCHITEM);
			return;
		}

		intializeItemRepresentation(theItem);

		for (ImageInfo theImage : imagesInfo) {
			addLinksForEntity("ItemImage", ImageInfoRepresentation.createItemImageLinks(theImage, cacheable));
		}
	}

	public static Map<RestAction, String> createItemLinks(Item theItem) {

		Map<RestAction, String> itemLinks = new HashMap<Representation.RestAction, String>();

		String path = null;
		Map<String, String> replacements = new HashMap<String, String>();

		replacements.put("itemId", theItem.getId().toString());

		// Link for READ item
		path = replaceTokens(ReadItemPath, replacements);
		itemLinks.put(RestAction.READ, path);

		// Link for UPDATE item
		path = replaceTokens(UpdateItemPath, replacements);
		itemLinks.put(RestAction.UPDATE, path);

		return itemLinks;
	}

	public Long getId() {
		return id;
	}

	public void setId(Long id) {
		this.id = id;
	}

	public String getName() {
		return name;
	}

	public void setName(String name) {
		this.name = name;
	}

	public String getManufacturer() {
		return manufacturer;
	}

	public void setManufacturer(String manufacturer) {
		this.manufacturer = manufacturer;
	}

	public Long getAuctionId() {
		return auctionId;
	}

	public void setAuctionId(Long auctionId) {
		this.auctionId = auctionId;
	}

	public Item.ItemState getState() {
		return state;
	}

	public void setState(Item.ItemState state) {
		this.state = state;
	}

	public Date getBiddingEndTime() {
		return biddingEndTime;
	}

	public void setBiddingEndTime(Date biddingEndTimeDate) {
		this.biddingEndTime = biddingEndTimeDate;
	}

	public Float getPurchasePrice() {
		return purchasePrice;
	}

	public void setPurchasePrice(Float purchasePrice) {
		this.purchasePrice = purchasePrice;
	}

	public String getLongDescription() {
		return longDescription;
	}

	public void setLongDescription(String longDescription) {
		this.longDescription = longDescription;
	}

	public Float getStartingBidAmount() {
		return startingBidAmount;
	}

	public void setStartingBidAmount(Float startingBidAmount) {
		this.startingBidAmount = startingBidAmount;
	}

	public Condition getCondition() {
		return condition;
	}

	public void setCondition(Condition condition) {
		this.condition = condition;
	}

	public Date getDateOfOrigin() {
		return dateOfOrigin;
	}

	public void setDateOfOrigin(Date dateOfOrigin) {
		this.dateOfOrigin = dateOfOrigin;
	}

	public Integer getBidCount() {
		return bidCount;
	}

	public void setBidCount(Integer bidCount) {
		this.bidCount = bidCount;
	}

	@Override
	public String toString() {
		String itemString;

		itemString = "Item Id: " + id + " Item Name: " + name + " Manufacturer: " + manufacturer;

		return itemString;
	}

}
