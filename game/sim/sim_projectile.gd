class_name SimProjectile
extends RefCounted
## bullet | lob | homing | acid (v2 adds shell, rocket, ram, ...)

var id := 0
var kind := "bullet"
var x := 0.0
var y := 0.0
var px := 0.0
var py := 0.0
var sx := 0.0
var sy := 0.0
var tx := 0.0
var ty := 0.0
var target_id := 0
var t := 0.0
var dur := 1.0
var speed := 0.0
var damage := 0.0
var tower := 0
var color := ""
var alive := true
