class_name ShopService
extends RefCounted
## 小卖部库存。进货按包，上机客点单按件，缺货只伤心情。

const CATALOG_PATH := "res://data/shop_catalog.json"

var catalog: Array = []
var stock: Dictionary = {}
var sold: Dictionary = {}
var missed := 0


func load_catalog() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null, "无法读取货架目录：%s" % CATALOG_PATH)
	var parsed = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and parsed.get("items") is Array, "shop_catalog.json 必须有 items")
	catalog = parsed["items"]
	assert(catalog.size() >= 3, "第一批货架至少 3 个 SKU")
	for item in catalog:
		assert(str(item.get("id", "")) != "", "商品缺少 id")
		assert(int(item.get("buy", 0)) > 0 and int(item.get("sell", 0)) > 0, "商品必须有进货价和售价")
	reset()


func reset() -> void:
	stock.clear()
	sold.clear()
	missed = 0
	for item in catalog:
		var item_id := str(item["id"])
		stock[item_id] = int(item.get("start", 0))
		sold[item_id] = 0


func begin_day() -> void:
	missed = 0
	for item in catalog:
		sold[str(item["id"])] = 0


func to_dict() -> Dictionary:
	return {
		"stock": stock.duplicate(),
		"sold": sold.duplicate(),
		"missed": missed,
	}


func from_dict(data: Dictionary) -> void:
	if data.is_empty():
		reset()
		return
	for item in catalog:
		var item_id := str(item["id"])
		var saved: Dictionary = data.get("stock", {})
		stock[item_id] = int(saved.get(item_id, item.get("start", 0)))
		var sold_saved: Dictionary = data.get("sold", {})
		sold[item_id] = int(sold_saved.get(item_id, 0))
	missed = int(data.get("missed", 0))


func item(item_id: String) -> Dictionary:
	for row in catalog:
		if str(row.get("id", "")) == item_id:
			return row
	return {}


func stock_of(item_id: String) -> int:
	return int(stock.get(item_id, 0))


func total_stock() -> int:
	var total := 0
	for item_id in stock.keys():
		total += int(stock[item_id])
	return total


func empty_count() -> int:
	var total := 0
	for item in catalog:
		if stock_of(str(item["id"])) <= 0:
			total += 1
	return total


func pack_cost(item_id: String) -> int:
	var row := item(item_id)
	if row.is_empty():
		return 0
	return int(row["buy"]) * int(row["pack"])


func pack_size(item_id: String) -> int:
	return int(item(item_id).get("pack", 0))


func today_sold_count() -> int:
	var total := 0
	for item_id in sold.keys():
		total += int(sold[item_id])
	return total


func restock(item_id: String, host: Node) -> bool:
	var row := item(item_id)
	if row.is_empty():
		return false
	var cost := pack_cost(item_id)
	if not host.spend(cost, "进货 %s" % row["name"], "shop_buy:%s" % item_id):
		return false
	stock[item_id] = stock_of(item_id) + int(row["pack"])
	return true


func sell(item_id: String, host: Node) -> bool:
	var row := item(item_id)
	if row.is_empty() or stock_of(item_id) <= 0:
		return false
	stock[item_id] = stock_of(item_id) - 1
	sold[item_id] = int(sold.get(item_id, 0)) + 1
	host.earn(int(row["sell"]), "商品 %s" % row["name"], "shop:%s" % item_id)
	return true


func miss() -> void:
	missed += 1


func pick_item(rng: RandomNumberGenerator, focus: String) -> String:
	var weights := {"cola": 50, "noodles": 35, "smokes": 15}
	if focus.contains("饮料") or focus.contains("零食"):
		weights = {"cola": 45, "noodles": 45, "smokes": 10}
	elif focus.contains("包夜"):
		weights = {"cola": 30, "noodles": 30, "smokes": 40}
	elif focus.contains("咖啡"):
		weights = {"cola": 60, "noodles": 30, "smokes": 10}
	var total := 0
	for item_id in weights.keys():
		total += int(weights[item_id])
	var roll := rng.randi_range(1, maxi(1, total))
	var acc := 0
	for item_id in weights.keys():
		acc += int(weights[item_id])
		if roll <= acc:
			return str(item_id)
	return "cola"


func stock_lines() -> String:
	var lines: Array[String] = []
	for row in catalog:
		var item_id := str(row["id"])
		lines.append("%s ¥%d  剩 %d" % [row["name"], int(row["sell"]), stock_of(item_id)])
	return "\n".join(lines)
