class_name Weapons
extends RefCounted
## Mk I weapon modules (section 9.2), built from the kit. Every module points along +X,
## sits on a turret ring at y = 0 and returns {head, barrel, muzzle, spin} nodes for animation.
## glow = the tower's piece-colour glow; scale grows with mass and stories.


static func build(type: String, parent: Node3D, glow_c: Color, s: float) -> Dictionary:
	var head := Node3D.new()
	head.name = "Head"
	parent.add_child(head)
	head.scale = Vector3.ONE * s
	var gm := Kit.glow(glow_c, 2.6)
	var out := {"head": head, "barrel": null, "muzzle": Vector3(0.8, 0.25, 0), "spin": null}
	# turret ring
	Kit.add(head, Kit.cylinder(0.42, 0.46, 0.14, 16), Kit.dark_iron(), Vector3(0, 0.07, 0))
	Kit.add(head, Kit.torus(0.4, 0.47, 16), gm, Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
	match type:
		"Gun":
			Kit.add(head, Kit.bevel_box(Vector3(0.62, 0.34, 0.5), 0.05), Kit.iron(), Vector3(0, 0.32, 0))
			var bar := Node3D.new()
			head.add_child(bar)
			bar.position = Vector3(0.2, 0.34, 0)
			for z in [-0.12, 0.12]:
				Kit.add(bar, Kit.cylinder(0.055, 0.065, 0.62, 10), Kit.dark_iron(), Vector3(0.3, 0, z), Vector3(0, 0, PI / 2))
				Kit.add(bar, Kit.cylinder(0.075, 0.075, 0.06, 10), Kit.brass(), Vector3(0.6, 0, z), Vector3(0, 0, PI / 2))
			Kit.add(head, Kit.box(Vector3(0.3, 0.06, 0.52)), gm, Vector3(-0.1, 0.5, 0))
			out.barrel = bar
			out.muzzle = Vector3(0.95, 0.34, 0)
		"Machine Gun":
			Kit.add(head, Kit.bevel_box(Vector3(0.5, 0.36, 0.48), 0.05), Kit.iron(), Vector3(-0.05, 0.32, 0))
			Kit.add(head, Kit.box(Vector3(0.22, 0.2, 0.2)), Kit.brass(), Vector3(-0.1, 0.3, 0.32))
			var bar2 := Node3D.new()
			head.add_child(bar2)
			bar2.position = Vector3(0.2, 0.34, 0)
			var spin := Node3D.new()
			bar2.add_child(spin)
			for i in 6:
				var a := TAU * i / 6.0
				Kit.add(spin, Kit.cylinder(0.03, 0.03, 0.7, 6), Kit.dark_iron(), Vector3(0.35, cos(a) * 0.08, sin(a) * 0.08), Vector3(0, 0, PI / 2))
			Kit.add(spin, Kit.torus(0.06, 0.13, 12), Kit.brass(), Vector3(0.55, 0, 0), Vector3(0, 0, PI / 2))
			Kit.add(spin, Kit.torus(0.06, 0.13, 12), Kit.brass(), Vector3(0.15, 0, 0), Vector3(0, 0, PI / 2))
			Kit.add(head, Kit.box(Vector3(0.06, 0.05, 0.3)), gm, Vector3(-0.32, 0.42, 0))
			out.barrel = bar2
			out.spin = spin
			out.muzzle = Vector3(0.95, 0.34, 0)
		"Rifle":
			Kit.add(head, Kit.bevel_box(Vector3(0.5, 0.3, 0.36), 0.04), Kit.iron(), Vector3(-0.08, 0.3, 0))
			var bar3 := Node3D.new()
			head.add_child(bar3)
			bar3.position = Vector3(0.1, 0.36, 0)
			Kit.add(bar3, Kit.cylinder(0.045, 0.06, 1.3, 10), Kit.dark_iron(), Vector3(0.62, 0, 0), Vector3(0, 0, PI / 2))
			Kit.add(bar3, Kit.cylinder(0.08, 0.08, 0.14, 10), Kit.brass(), Vector3(1.24, 0, 0), Vector3(0, 0, PI / 2))
			# scope with lens glint
			Kit.add(bar3, Kit.cylinder(0.05, 0.05, 0.42, 10), Kit.iron(), Vector3(0.05, 0.14, 0), Vector3(0, 0, PI / 2))
			Kit.add(bar3, Kit.cylinder(0.045, 0.045, 0.02, 10), Kit.glow(Color(0.6, 0.9, 1.0), 4.0), Vector3(0.27, 0.14, 0), Vector3(0, 0, PI / 2))
			out.barrel = bar3
			out.muzzle = Vector3(1.4, 0.36, 0)
		"Bomb":
			Kit.add(head, Kit.cylinder(0.36, 0.42, 0.24, 14), Kit.iron(), Vector3(0, 0.22, 0))
			var bar4 := Node3D.new()
			head.add_child(bar4)
			bar4.position = Vector3(0, 0.3, 0)
			bar4.rotation = Vector3(0, 0, deg_to_rad(-55))
			Kit.add(bar4, Kit.cylinder(0.2, 0.24, 0.5, 14), Kit.dark_iron(), Vector3(0, 0.25, 0))
			Kit.add(bar4, Kit.torus(0.18, 0.26, 14), Kit.brass(), Vector3(0, 0.5, 0))
			Kit.add(bar4, Kit.cylinder(0.17, 0.17, 0.02, 14), gm, Vector3(0, 0.49, 0))
			out.barrel = bar4
			out.muzzle = Vector3(0.4, 0.8, 0)
		"Missile":
			Kit.add(head, Kit.bevel_box(Vector3(0.6, 0.18, 0.6), 0.04), Kit.iron(), Vector3(0, 0.2, 0))
			var bar5 := Node3D.new()
			head.add_child(bar5)
			bar5.position = Vector3(0, 0.45, 0)
			bar5.rotation = Vector3(0, 0, deg_to_rad(-20))
			Kit.add(bar5, Kit.bevel_box(Vector3(0.6, 0.4, 0.56), 0.05), Kit.dark_iron(), Vector3.ZERO)
			for iy in 2:
				for iz in 2:
					var p := Vector3(0.31, -0.09 + iy * 0.18, -0.13 + iz * 0.26)
					Kit.add(bar5, Kit.cylinder(0.07, 0.07, 0.03, 10), Kit.dark_iron(), p, Vector3(0, 0, PI / 2))
					Kit.add(bar5, Kit.sphere(0.055, 8), Kit.glow(Color(1, 0.4, 0.2), 2.0), p + Vector3(-0.01, 0, 0))
			Kit.add(bar5, Kit.box(Vector3(0.62, 0.04, 0.58)), gm, Vector3(0, 0.22, 0))
			out.barrel = bar5
			out.muzzle = Vector3(0.6, 0.6, 0)
		"Laser":
			Kit.add(head, Kit.cylinder(0.3, 0.36, 0.2, 14), Kit.iron(), Vector3(0, 0.2, 0))
			var bar6 := Node3D.new()
			head.add_child(bar6)
			bar6.position = Vector3(0, 0.55, 0)
			for z in [-0.22, 0.22]:
				Kit.add(head, Kit.box(Vector3(0.1, 0.5, 0.06)), Kit.brass(), Vector3(0, 0.5, z))
			var crystal := Kit.add(bar6, Kit.sphere(0.2, 6), Kit.glow(glow_c, 4.0), Vector3(0.05, 0, 0), Vector3.ZERO, Vector3(1.6, 0.8, 0.8))
			crystal.name = "Crystal"
			Kit.add(bar6, Kit.cylinder(0.06, 0.1, 0.3, 10), Kit.dark_iron(), Vector3(0.35, 0, 0), Vector3(0, 0, PI / 2))
			out.barrel = bar6
			out.muzzle = Vector3(0.55, 0.55, 0)
		"Pulsar":
			Kit.add(head, Kit.cylinder(0.32, 0.38, 0.22, 14), Kit.iron(), Vector3(0, 0.2, 0))
			var bar7 := Node3D.new()
			head.add_child(bar7)
			bar7.position = Vector3(0, 0.45, 0)
			Kit.add(bar7, Kit.cylinder(0.08, 0.08, 0.9, 10), Kit.dark_iron(), Vector3(0.35, 0, 0), Vector3(0, 0, PI / 2))
			for i in 4:
				Kit.add(bar7, Kit.torus(0.1, 0.2 - i * 0.02, 16), gm if i % 2 == 0 else Kit.brass(), Vector3(0.1 + i * 0.2, 0, 0), Vector3(0, 0, PI / 2))
			out.barrel = bar7
			out.muzzle = Vector3(0.85, 0.45, 0)
		"Lightning":
			Kit.add(head, Kit.cylinder(0.3, 0.38, 0.2, 14), Kit.iron(), Vector3(0, 0.2, 0))
			for i in 5:
				var r := 0.32 - i * 0.045
				Kit.add(head, Kit.torus(r * 0.6, r, 16), Kit.copper(), Vector3(0, 0.36 + i * 0.13, 0))
			Kit.add(head, Kit.cylinder(0.06, 0.08, 0.7, 8), Kit.dark_iron(), Vector3(0, 0.6, 0))
			var orb := Kit.add(head, Kit.sphere(0.17, 12), Kit.glow(Color(0.6, 0.85, 1.0), 4.5), Vector3(0, 1.06, 0))
			orb.name = "Orb"
			out.muzzle = Vector3(0, 1.06, 0)
		"E-Field":
			Kit.add(head, Kit.cylinder(0.38, 0.42, 0.18, 16), Kit.iron(), Vector3(0, 0.18, 0))
			Kit.dome(head, 0.36, 0.27, glow_c)
			Kit.add(head, Kit.cylinder(0.03, 0.03, 0.35, 6), Kit.brass(), Vector3(0, 0.75, 0))
			Kit.add(head, Kit.sphere(0.06, 8), gm, Vector3(0, 0.95, 0))
			out.muzzle = Vector3(0, 0.6, 0)
		"Freezer":
			Kit.add(head, Kit.bevel_box(Vector3(0.5, 0.32, 0.46), 0.05), Kit.iron(), Vector3(-0.05, 0.3, 0))
			var bar8 := Node3D.new()
			head.add_child(bar8)
			bar8.position = Vector3(0.18, 0.36, 0)
			Kit.add(bar8, Kit.cylinder(0.16, 0.09, 0.42, 12), Kit.brass(), Vector3(0.25, 0, 0), Vector3(0, 0, -PI / 2))
			Kit.add(bar8, Kit.cylinder(0.14, 0.14, 0.02, 12), Kit.glow(Color(0.55, 0.9, 1.0), 3.5), Vector3(0.47, 0, 0), Vector3(0, 0, PI / 2))
			for z in [-0.25, 0.25]:
				Kit.add(head, Kit.cylinder(0.08, 0.08, 0.36, 10), Kit.glass(Color(0.5, 0.85, 1.0)), Vector3(-0.15, 0.4, z))
			out.barrel = bar8
			out.muzzle = Vector3(0.75, 0.36, 0)
		"Flamer":
			Kit.add(head, Kit.cylinder(0.24, 0.3, 0.44, 12), Kit.copper(), Vector3(-0.12, 0.34, 0))
			Kit.add(head, Kit.sphere(0.24, 12, true), Kit.copper(), Vector3(-0.12, 0.56, 0))
			var bar9 := Node3D.new()
			head.add_child(bar9)
			bar9.position = Vector3(0.1, 0.36, 0)
			Kit.add(bar9, Kit.cylinder(0.06, 0.09, 0.5, 10), Kit.dark_iron(), Vector3(0.25, 0, 0), Vector3(0, 0, PI / 2))
			var pilot := Kit.add(bar9, Kit.sphere(0.05, 8), Kit.glow(Color(0.4, 0.7, 1.0), 4.0), Vector3(0.52, -0.06, 0))
			pilot.name = "Pilot"
			out.barrel = bar9
			out.muzzle = Vector3(0.65, 0.36, 0)
		"Acid":
			Kit.add(head, Kit.cylinder(0.34, 0.3, 0.4, 14), Kit.copper(), Vector3(0, 0.3, 0))
			Kit.add(head, Kit.torus(0.3, 0.37, 14), Kit.dark_iron(), Vector3(0, 0.5, 0))
			var goo := Kit.add(head, Kit.cylinder(0.3, 0.3, 0.02, 14), Kit.glow(Color(0.5, 1.0, 0.2), 3.0), Vector3(0, 0.49, 0))
			goo.name = "Goo"
			var bar10 := Node3D.new()
			head.add_child(bar10)
			bar10.position = Vector3(0.2, 0.55, 0)
			bar10.rotation = Vector3(0, 0, deg_to_rad(-35))
			Kit.add(bar10, Kit.box(Vector3(0.06, 0.5, 0.06)), Kit.dark_iron(), Vector3(0, 0.22, 0))
			Kit.add(bar10, Kit.sphere(0.09, 8, true), Kit.brass(), Vector3(0, 0.47, 0), Vector3(PI, 0, 0))
			out.barrel = bar10
			out.muzzle = Vector3(0.3, 0.95, 0)
		"Virus":
			Kit.add(head, Kit.cylinder(0.32, 0.38, 0.2, 14), Kit.iron(), Vector3(0, 0.18, 0))
			for i in 3:
				var a := TAU * i / 3.0
				var p := Vector3(cos(a) * 0.2, 0.42, sin(a) * 0.2)
				Kit.add(head, Kit.cylinder(0.03, 0.03, 0.25, 6), Kit.brass(), p - Vector3(0, 0.12, 0))
				Kit.add(head, Kit.sphere(0.13, 10), Kit.glass(Color(0.75, 1.0, 0.35)), p + Vector3(0, 0.08, 0))
				Kit.add(head, Kit.sphere(0.07, 8), Kit.glow(Color(0.6, 1.0, 0.3), 3.0), p + Vector3(0, 0.08, 0))
			out.muzzle = Vector3(0, 0.6, 0)
		_:
			Kit.add(head, Kit.bevel_box(Vector3(0.5, 0.3, 0.5), 0.05), Kit.iron(), Vector3(0, 0.3, 0))
	return out
