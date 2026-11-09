## 港口设施门的触发区。slot = 设施码 0..11（SNR 事件键低字节，见 data/facilities.json），门放哪都行，槽号不能变。
class_name PortDoor
extends Area3D

@export_range(0, 11) var slot := 0
