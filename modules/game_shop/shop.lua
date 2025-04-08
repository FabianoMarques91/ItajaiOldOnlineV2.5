local SHOP_EXTENTED_OPCODE = 201

shop = nil
local otcv8shop = false
local shopButton = nil
local msgWindow = nil
local browsingHistory = false

-- for classic store
local storeUrl = ""
local coinsPacketSize = 0

local CATEGORIES = {}
local HISTORY = {}
local STATUS = {}

local selectedOffer = {}

local ShopCategory = {
  Items  = 1,
  Outfits = 2,
  Decoractions = 3,
  Scrolls = 3
}

local function sendAction(action, data)
  local protocolGame = g_game.getProtocolGame()
  if data == nil then
    data = {}
  end
  if protocolGame then
    protocolGame:sendExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, {action = action, data = data})
  end  
end

-- public functions
function init()
  connect(g_game, {
    onGameStart = check, 
    onGameEnd = hide,  
  })

  ProtocolGame.registerExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)
  
  if g_game.isOnline() then
    check()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = check, 
    onGameEnd = hide,
  })

  ProtocolGame.unregisterExtendedJSONOpcode(SHOP_EXTENTED_OPCODE, onExtendedJSONOpcode)
  
  if shopButton then
    shopButton:destroy()
    shopButton = nil
  end
  if shop then
    disconnect(shop.categories, { onChildFocusChange = changeCategory })
    shop:destroy()
    shop = nil
  end
  if msgWindow then
    msgWindow:destroy()
  end
  
  g_keyboard.unbindKeyDown('Alt+S')
end

function check()
  otcv8shop = false
  sendAction("init")
end

function hide()
  if not shop then
    return
  end
  shop:hide()
end

function show()
  if not shop or not shopButton then
    return
  end
  if g_game.getFeature(GameIngameStore) then
    g_game.openStore(0)
  end
  
  shop:show()
  shop:raise()
  shop:focus()
end

function toggle()
  if not shop then
    return
  end
  if shop:isVisible() then
    return hide()
  end
  show()
  check()
end

function createShop()
  if shop then return end
  shop = g_ui.displayUI('shop')
  shop:hide()
  shopButton = modules.client_topmenu.addLeftGameButton('shopButton', tr('Shop'), '/images/topbuttons/shop', toggle, false, 8)
  connect(shop.categories, { onChildFocusChange = changeCategory })
end

function onExtendedJSONOpcode(protocol, code, json_data)
  createShop()

  local action = json_data['action']
  local data = json_data['data']
  local status = json_data['status']
 
  if not action or not data then
    return false
  end
  
  otcv8shop = true
  if action == 'categories' then
    processCategories(data)
  elseif action == 'history' then
    processHistory(data)
  elseif action == 'message' then
    processMessage(data)  
  end
  
  if status then
    processStatus(status)
  end
end

function clearOffers()
  while shop.offers:getChildCount() > 0 do
    local child = shop.offers:getLastChild()
    shop.offers:destroyChildren(child)
  end
end

function clearCategories()
  CATEGORIES = {}
  clearOffers()
  while shop.categories:getChildCount() > 0 do
    local child = shop.categories:getLastChild()
    shop.categories:destroyChildren(child)
  end
end

function clearHistory()
  HISTORY = {}
  if browsingHistory then
    clearOffers()
  end
end

function processCategories(data)
  if table.equal(CATEGORIES,data) then
    return
  end
  clearCategories()
  CATEGORIES = data
  for i, category in ipairs(data) do
    addCategory(category)
  end

  if not browsingHistory then
    local firstCategory = shop.categories:getChildByIndex(1)
    if firstCategory then
      firstCategory:focus()
    end
  end
end

function processHistory(data)
  if table.equal(HISTORY,data) then
    return
  end
  HISTORY = data
  if browsingHistory then
    showHistory(true)
  end
end

function processMessage(data)
  if msgWindow then
    msgWindow:destroy()
  end
    
  local title = data["title"]
  local msg = data["msg"]
  msgWindow = displayInfoBox(title, msg)
  msgWindow.onDestroy = function(widget)
    if widget == msgWindow then
      msgWindow = nil
    end
  end
  msgWindow:show()
  msgWindow:raise()
  msgWindow:focus()
end

function processStatus(data)
  if table.equal(STATUS, data) then
    return
  end
  STATUS = data
  if data['points'] then
    shop.infoPanel.points:setText(tostring(data['points']))
  end
end


function addCategory(data)
  local category = g_ui.createWidget('ShopCategory', shop.categories)  
  
  category:setId("category_" .. shop.categories:getChildCount())
  category:setText(data["name"])
end

function showHistory(force)
  if browsingHistory and not force then
    return
  end

  sendAction("history")

  browsingHistory = true
 
  clearOffers()    
  shop.categories:focusChild(nil)
  for i, transaction in ipairs(HISTORY) do
    addOffer(0, transaction)
  end
end

function addOffer(category, data)  
  local offer
  if data["item"] then
    offer = g_ui.createWidget('ShopOfferItem', shop.offers)  
    offer.item:setItemId(data["item"])
  elseif data["outfit"] then
    offer = g_ui.createWidget('ShopOfferCreature', shop.offers)
    offer.creature:setOutfit(data["outfit"])
  elseif data["image"] then
    offer = g_ui.createWidget('ShopOfferImage', shop.offers)
    if data["image"]:sub(1, 4):lower() == "http" then
      HTTP.downloadImage(data["image"], function(path, err) 
        if err then g_logger.warning("HTTP error: " .. err .. " - " .. data['image']) return end
        if not offer.image then return end
        offer.image:setImageSource(path)
      end)
    elseif data["image"]:len() > 1 then
      offer.image:setImageSource(data["image"])
    end
  else
    g_logger.error("Invalid shop offer categoryId: " .. tostring(category))
    return
  end
  offer:setId("offer_" .. category .. "_" .. shop.offers:getChildCount())
  offer.title:setText(data["name"])
  offer.points:setText(data["price"])
  offer:setTooltip(data["description"])  
  offer.offerId = data["id"]
  if category ~= 0 then
    offer.onDoubleClick = buyOffer
  end
end

function changeCategory(widget, newCategory)
  if not newCategory then
    return
  end
  
  browsingHistory = false
  clearOffers()
  
  local id = tonumber(newCategory:getId():split("_")[2])
  for i, offer in ipairs(CATEGORIES[id]["offers"]) do
    addOffer(id, offer)
  end
end

function buyOffer(widget)
  if not widget then
    return
  end
  local split = widget:getId():split("_")
  if #split ~= 3 then
    return
  end
  local category = tonumber(split[2])  
  local offer = tonumber(split[3])  
  local item = CATEGORIES[category]["offers"][offer]
  if not item then
    return
  end
  
  selectedOffer = {category=category, offer=offer, name=item.name, price=item.price, id=widget.offerId}
  
  scheduleEvent(function()
      if msgWindow then
        msgWindow:destroy()
      end
      
      local title = tr("Comprando na loja")
      local msg = tr("Você tem certeza que quer comprar %s por %s wod coins?", item.name, item.price)
      msgWindow = displayGeneralBox(title, msg, {
          { text=tr('Yes'), callback=buyConfirmed },
          { text=tr('No'), callback=buyCanceled },
          anchor=AnchorHorizontalCenter}, buyConfirmed, buyCanceled)
      msgWindow:show()
      msgWindow:raise()
      msgWindow:focus()
      msgWindow:raise()
    end, 50)
end

function processStatus(data)
  if table.equal(STATUS,data) then
    return
  end
  STATUS = data

  if data['points'] then
    shop.infoPanel.points:setText(data['points'])
  end
  if data['buyUrl'] and data['buyUrl']:sub(1, 4):lower() == "http" then
    shop.buyPoints.onMouseRelease = function() 
      scheduleEvent(function() g_platform.openUrl(data['buyUrl']) end, 50)
    end
  end
end

function buyConfirmed()
  msgWindow:destroy()
  msgWindow = nil
  sendAction("buy", selectedOffer) 
end

function buyCanceled()
  msgWindow:destroy()
  msgWindow = nil
  selectedOffer = {}
end
