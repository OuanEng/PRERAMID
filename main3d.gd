extends Node3D

const TOTAL := 819
const SUPPLY := Vector3(-32, 0, 0)
const BUILD := Vector3(20, 0, 0)
const PYRAMID := Vector3(34, 0, 0)
const SAVE_PREFIX := "user://preramid_"

var mode := ""
var placed := 0
var carried := false
var seconds_played := 0.0
var coins := 0
var upgrades := [false, false, false]
var player_position := Vector3(-18, 0, 0)
var save_timer := 0.0
var hint := ""
var hint_time := 0.0
var shop_open := false
var camera_yaw := 0.0
var camera_pitch := 0.0
var storm_time := 0.0

var player_root: Node3D
var carried_block: MeshInstance3D
var view_block: MeshInstance3D
var cart_root: Node3D
var camera: Camera3D
var desert_environment: Environment
var sand_particles: CPUParticles3D
var supply_ring: MeshInstance3D
var build_ring: MeshInstance3D
var pyramid_layers: Array[MultiMeshInstance3D] = []
var hud_title: Label
var hud_info: Label
var hud_prompt: Label
var hud_direction: Label
var menu_panel: PanelContainer
var shop_panel: PanelContainer
var shop_buttons: Array[Button] = []

func _ready() -> void:
	build_world()
	build_ui()
	update_ui()
	update_player_visuals()

func material(color: Color, roughness: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	return mat

func textured_material(texture: Texture2D, tint: Color, repeat_scale: Vector3 = Vector3.ONE) -> StandardMaterial3D:
	var mat := material(tint)
	mat.albedo_texture = texture
	mat.uv1_scale = repeat_scale
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

func make_texture(kind: String) -> ImageTexture:
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 2718 if kind == "sand" else (1618 if kind == "path" else 3141)
	noise.frequency = 0.055
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var grain := FastNoiseLite.new()
	grain.seed = noise.seed + 97
	grain.frequency = 0.28
	var base := Color("a78d6a") if kind == "sand" else (Color("9d805e") if kind == "path" else Color("b99b75"))
	for y in range(size):
		for x in range(size):
			var broad := noise.get_noise_2d(float(x), float(y))
			var fine := grain.get_noise_2d(float(x), float(y))
			var variation := broad * 0.10 + fine * 0.045
			if kind == "sand":
				variation += sin(float(y) * 0.24 + broad * 4.0) * 0.018
			elif kind == "stone":
				variation += sin(float(y) * 0.17 + broad * 2.0) * 0.035
				if y % 43 < 2: variation -= 0.08
			else:
				if x % 32 < 2 or y % 32 < 2: variation -= 0.10
			var color := base.lightened(variation) if variation >= 0.0 else base.darkened(-variation)
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func box(parent: Node3D, name: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = position
	parent.add_child(node)
	return node

func cylinder(parent: Node3D, name: String, radius: float, height: float, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	node.mesh = mesh
	node.material_override = material(color)
	node.position = position
	parent.add_child(node)
	return node

func sphere(parent: Node3D, name: String, radius: float, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = name
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	node.mesh = mesh
	node.material_override = material(color)
	node.position = position
	parent.add_child(node)
	return node

func build_world() -> void:
	var environment := WorldEnvironment.new()
	desert_environment = Environment.new()
	desert_environment.background_mode = Environment.BG_COLOR
	desert_environment.background_color = Color("869a9d")
	desert_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	desert_environment.ambient_light_color = Color("c5b3a0")
	desert_environment.ambient_light_energy = 0.30
	desert_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	desert_environment.fog_enabled = true
	desert_environment.fog_light_color = Color("aa9a86")
	desert_environment.fog_density = 0.006
	environment.environment = desert_environment
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_color = Color("e8c69a")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	var sand_texture := make_texture("sand")
	var path_texture := make_texture("path")
	var stone_texture := make_texture("stone")
	var stone_material := textured_material(stone_texture, Color("d2bb9a"))
	var ground := box(self, "Desert", Vector3(160, 0.3, 100), Vector3(0, -0.22, 0), Color.WHITE)
	ground.material_override = textured_material(sand_texture, Color("c4b093"), Vector3(48, 1, 30))
	var path := box(self, "Carrying path", Vector3(70, 0.06, 6.5), Vector3(0, -0.03, 0), Color.WHITE)
	path.material_override = textured_material(path_texture, Color("c9b393"), Vector3(30, 1, 3))
	for i in range(24):
		var x := float((i * 31) % 120) - 60.0
		var z := float((i * 19) % 57) - 28.0
		if absf(z) < 7.0: z += 13.0
		var pebble := box(self, "Sand stone %d" % i, Vector3(1.5 + (i % 4), 0.3, 1.4 + (i % 3)), Vector3(x, 0.02, z), Color.WHITE)
		pebble.material_override = stone_material
	# Supply and its permanent stack of uncarried stones.
	cylinder(self, "Supply base", 5.5, 0.25, SUPPLY + Vector3(0, 0.06, 0), Color("9d7652"))
	for row in range(3):
		for col in range(4 - row):
			for depth in range(3 - row):
				var supply_stone := box(self, "Supply stone", Vector3(1.6, 0.9, 1.4), SUPPLY + Vector3((col - 1.5 + row * 0.5) * 1.75, 0.6 + row * 0.9, (depth - 1) * 1.55), Color.WHITE)
				supply_stone.material_override = stone_material
	supply_ring = make_ring(SUPPLY, 4.1, Color("fbe5a7"))
	build_ring = make_ring(BUILD, 4.4, Color("ffce65"))
	var plinth := box(self, "Pyramid plinth", Vector3(23, 0.55, 23), PYRAMID + Vector3(0, 0.2, 0), Color.WHITE)
	plinth.material_override = textured_material(stone_texture, Color("9f8368"), Vector3(10, 1, 10))
	for tier in range(13):
		var instance := MultiMeshInstance3D.new()
		instance.name = "Pyramid tier %d" % (tier + 1)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.54, 1.25, 1.54)
		mm.mesh = mesh
		mm.instance_count = 0
		instance.multimesh = mm
		instance.material_override = textured_material(stone_texture, Color("d0b693") if tier % 2 == 0 else Color("c3a781"))
		add_child(instance)
		pyramid_layers.append(instance)
	for i in range(8):
		var pos := Vector3(-48 + i * 13, 0, -15 if i % 2 == 0 else 16)
		make_obelisk(pos)
	player_root = Node3D.new()
	player_root.name = "Builder"
	add_child(player_root)
	cylinder(player_root, "Body", 0.42, 1.4, Vector3(0, 1.2, 0), Color("377b7d"))
	sphere(player_root, "Head", 0.37, Vector3(0, 2.15, 0), Color("a66a45"))
	box(player_root, "Left leg", Vector3(0.23, 0.8, 0.28), Vector3(-0.18, 0.4, 0), Color("584c41"))
	box(player_root, "Right leg", Vector3(0.23, 0.8, 0.28), Vector3(0.18, 0.4, 0), Color("584c41"))
	box(player_root, "Left arm", Vector3(0.22, 0.85, 0.24), Vector3(-0.58, 1.28, 0), Color("b87d55"))
	box(player_root, "Right arm", Vector3(0.22, 0.85, 0.24), Vector3(0.58, 1.28, 0), Color("b87d55"))
	carried_block = box(player_root, "Carried brick", Vector3(1.3, 0.72, 0.9), Vector3(0, 2.72, -0.08), Color.WHITE)
	carried_block.material_override = stone_material
	cart_root = Node3D.new()
	cart_root.name = "Cart"
	player_root.add_child(cart_root)
	box(cart_root, "Cart bed", Vector3(1.8, 0.2, 1.1), Vector3(0, 0.5, 1.15), Color("785638"))
	for side in [-0.75, 0.75]:
		cylinder(cart_root, "Cart wheel", 0.26, 0.16, Vector3(side, 0.27, 1.15), Color("49382c"))
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 75.0
	camera.near = 0.04
	add_child(camera)
	view_block = box(camera, "Brick in hands", Vector3(0.65, 0.36, 0.42), Vector3(0.58, -0.48, -0.85), Color.WHITE)
	view_block.material_override = stone_material
	view_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	make_sandstorm_particles()
	refresh_pyramid()

func make_sandstorm_particles() -> void:
	sand_particles = CPUParticles3D.new()
	sand_particles.name = "Windblown sand"
	sand_particles.amount = 360
	sand_particles.lifetime = 3.8
	sand_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sand_particles.emission_box_extents = Vector3(16, 4, 14)
	sand_particles.direction = Vector3(1, 0.1, 0.4).normalized()
	sand_particles.spread = 16.0
	sand_particles.gravity = Vector3.ZERO
	sand_particles.initial_velocity_min = 4.0
	sand_particles.initial_velocity_max = 8.0
	sand_particles.local_coords = false
	sand_particles.color = Color(0.76, 0.61, 0.39, 0.45)
	var speck := QuadMesh.new()
	speck.size = Vector2(0.13, 0.13)
	var speck_material := StandardMaterial3D.new()
	speck_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	speck_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	speck_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	speck_material.albedo_color = Color(0.83, 0.69, 0.47, 0.44)
	speck.material = speck_material
	sand_particles.mesh = speck
	sand_particles.position = player_position + Vector3(0, 2.2, 0)
	add_child(sand_particles)
	sand_particles.emitting = true

func make_ring(center: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.16
	mesh.outer_radius = radius
	ring.mesh = mesh
	ring.position = center + Vector3(0, 0.08, 0)
	var mat := material(color)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.8
	ring.material_override = mat
	add_child(ring)
	return ring

func make_obelisk(pos: Vector3) -> void:
	box(self, "Obelisk", Vector3(1.4, 5.0, 1.4), pos + Vector3(0, 2.5, 0), Color("b48e65"))
	var point := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.4, 1.0, 1.4)
	point.mesh = mesh
	point.material_override = material(Color("d5ad75"))
	point.position = pos + Vector3(0, 5.45, 0)
	add_child(point)

func refresh_pyramid() -> void:
	var remaining := placed
	for tier in range(13):
		var side := 13 - tier
		var count := mini(remaining, side * side)
		var mm := pyramid_layers[tier].multimesh
		mm.instance_count = count
		for n in range(count):
			var col := n % side
			var row := n / side
			var p := PYRAMID + Vector3((float(col) - (side - 1) * 0.5) * 1.55, 0.95 + tier * 1.27, (float(row) - (side - 1) * 0.5) * 1.55)
			mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, p))
		remaining -= count

func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hud := PanelContainer.new()
	hud.position = Vector2(16, 15)
	hud.custom_minimum_size = Vector2(550, 112)
	layer.add_child(hud)
	var hud_box := VBoxContainer.new()
	hud.add_child(hud_box)
	hud_title = Label.new()
	hud_title.add_theme_font_size_override("font_size", 25)
	hud_box.add_child(hud_title)
	hud_info = Label.new()
	hud_info.add_theme_font_size_override("font_size", 17)
	hud_box.add_child(hud_info)
	hud_direction = Label.new()
	hud_direction.add_theme_font_size_override("font_size", 17)
	hud_box.add_child(hud_direction)
	hud_prompt = Label.new()
	hud_prompt.position = Vector2(20, 655)
	hud_prompt.size = Vector2(1230, 45)
	hud_prompt.add_theme_font_size_override("font_size", 19)
	layer.add_child(hud_prompt)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.position = Vector2(628, 337)
	crosshair.add_theme_font_size_override("font_size", 25)
	crosshair.add_theme_color_override("font_color", Color("fff2d0"))
	layer.add_child(crosshair)
	menu_panel = PanelContainer.new()
	menu_panel.position = Vector2(405, 160)
	menu_panel.custom_minimum_size = Vector2(470, 365)
	layer.add_child(menu_panel)
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 13)
	menu_panel.add_child(menu)
	var title := Label.new()
	title.text = "PRERAMID 3D"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	menu.add_child(title)
	var description := Label.new()
	description.text = "ขนอิฐทีละก้อน • พีระมิด 13 ชั้น • 819 ก้อน"
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(description)
	var normal := Button.new()
	normal.text = "NORMAL — มีตัวช่วย"
	normal.custom_minimum_size.y = 55
	normal.pressed.connect(start_game.bind("normal"))
	menu.add_child(normal)
	var hard := Button.new()
	hard.text = "HARD — ไม่มีตัวช่วย"
	hard.custom_minimum_size.y = 55
	hard.pressed.connect(start_game.bind("hard"))
	menu.add_child(hard)
	var controls := Label.new()
	controls.text = "เมาส์: มองรอบตัว    WASD / ลูกศร: เดิน\nE / Space: หยิบ-วาง    B: ร้าน    Esc: เมนู\nบันทึกอัตโนมัติแยกแต่ละโหมด"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(controls)
	shop_panel = PanelContainer.new()
	shop_panel.position = Vector2(968, 125)
	shop_panel.custom_minimum_size = Vector2(290, 300)
	layer.add_child(shop_panel)
	var shop := VBoxContainer.new()
	shop.add_theme_constant_override("separation", 8)
	shop_panel.add_child(shop)
	var shop_title := Label.new()
	shop_title.text = "ร้านตัวช่วย (Normal)"
	shop_title.add_theme_font_size_override("font_size", 20)
	shop.add_child(shop_title)
	var names := ["รองเท้าเร็ว • 25 เหรียญ", "รถเข็น • 60 เหรียญ", "แผนที่ทางลัด • 110 เหรียญ"]
	for i in range(3):
		var button := Button.new()
		button.text = names[i]
		button.custom_minimum_size.y = 50
		button.pressed.connect(buy_upgrade.bind(i))
		shop.add_child(button)
		shop_buttons.append(button)
	var note := Label.new()
	note.text = "ตัวช่วยเพิ่มความเร็ว\nยังขนได้ทีละก้อนเท่านั้น"
	shop.add_child(note)
	shop_panel.hide()

func start_game(new_mode: String) -> void:
	mode = new_mode
	placed = 0
	carried = false
	seconds_played = 0.0
	coins = 0
	upgrades = [false, false, false]
	player_position = Vector3(-18, 0, 0)
	load_game()
	camera_yaw = -PI * 0.5 if carried else PI * 0.5
	camera_pitch = 0.0
	menu_panel.hide()
	shop_open = false
	shop_panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	refresh_pyramid()
	update_player_visuals()
	set_hint("เดินไปวงแหวนที่กองอิฐด้านซ้าย แล้วกด E")
	update_ui()

func _process(delta: float) -> void:
	if mode != "":
		storm_time += delta
		var gust := pow((sin(storm_time * 0.23) + 1.0) * 0.5, 3.0)
		desert_environment.fog_density = 0.007 + gust * 0.008
		sand_particles.position = player_position + Vector3(0, 2.2, 0)
		seconds_played += delta
		save_timer += delta
		if save_timer >= 10.0:
			save_timer = 0.0
			save_game()
		if hint_time > 0.0: hint_time -= delta
		var movement := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_key_pressed(KEY_A): movement.x -= 1.0
		if Input.is_key_pressed(KEY_D): movement.x += 1.0
		if Input.is_key_pressed(KEY_W): movement.y -= 1.0
		if Input.is_key_pressed(KEY_S): movement.y += 1.0
		movement = movement.normalized() if not shop_open else Vector2.ZERO
		if movement.length() > 0.0:
			var speed := 4.1
			if mode == "normal":
				speed = 6.0
				if upgrades[0]: speed += 1.0
				if upgrades[1]: speed += 0.9
				if upgrades[2]: speed += 1.1
			var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
			var forward := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
			player_position += (right * movement.x - forward * movement.y) * speed * delta
			player_position.x = clampf(player_position.x, -55, 55)
			player_position.z = clampf(player_position.z, -29, 29)
			player_root.rotation.y = camera_yaw
		player_root.position = player_position
		update_ui()
	camera.position = player_position + Vector3(0, 1.8, 0)
	camera.rotation = Vector3(camera_pitch, camera_yaw, 0)

func _unhandled_input(event: InputEvent) -> void:
	if mode != "" and not shop_open and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_yaw -= event.relative.x * 0.0025
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.0025, -1.35, 1.35)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		if mode != "":
			save_game()
			mode = ""
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			menu_panel.show()
			shop_panel.hide()
			update_ui()
		return
	if mode == "": return
	if event.keycode == KEY_B and mode == "normal":
		shop_open = not shop_open
		shop_panel.visible = shop_open
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if shop_open else Input.MOUSE_MODE_CAPTURED
	elif event.keycode == KEY_E or event.keycode == KEY_SPACE:
		interact()

func interact() -> void:
	if placed >= TOTAL:
		set_hint("พีระมิดสร้างสำเร็จแล้ว!")
		return
	if carried:
		if player_position.distance_to(BUILD) <= 4.5:
			carried = false
			placed += 1
			coins += 1
			refresh_pyramid()
			update_player_visuals()
			set_hint("สำเร็จ! ครบ 819 ก้อน" if placed == TOTAL else "วางแล้ว • กลับไปขนอิฐก้อนต่อไป")
			save_game()
		else:
			set_hint("ไปวงแหวนสีทองที่จุดก่อสร้างทางขวา")
	else:
		if player_position.distance_to(SUPPLY) <= 4.5:
			carried = true
			update_player_visuals()
			set_hint("หยิบอิฐแล้ว • ไปวงแหวนที่พีระมิดทางขวา")
			save_game()
		else:
			set_hint("ไปใกล้กองอิฐทางซ้าย")

func buy_upgrade(index: int) -> void:
	if mode != "normal" or upgrades[index]: return
	var costs := [25, 60, 110]
	if coins < costs[index]:
		set_hint("ต้องใช้ %d เหรียญ" % costs[index])
		return
	coins -= costs[index]
	upgrades[index] = true
	update_player_visuals()
	set_hint("ซื้อตัวช่วยแล้ว • เดินเร็วขึ้น")
	save_game()

func update_player_visuals() -> void:
	if player_root == null: return
	player_root.position = player_position
	player_root.visible = false
	carried_block.visible = false
	view_block.visible = carried
	cart_root.visible = mode == "normal" and upgrades[1]

func set_hint(message: String) -> void:
	hint = message
	hint_time = 5.0
	update_ui()

func update_ui() -> void:
	if mode == "":
		hud_title.text = "PRERAMID 3D"
		hud_info.text = "เลือกโหมดเพื่อเริ่มหรือเล่นต่อ"
		hud_direction.text = ""
		hud_prompt.text = ""
		return
	var hours := int(seconds_played) / 3600
	var minutes := (int(seconds_played) % 3600) / 60
	var secs := int(seconds_played) % 60
	hud_title.text = "%s  |  ชั้น %d/13  |  %d/819 ก้อน" % [mode.to_upper(), current_tier(), placed]
	hud_info.text = "เวลา %02d:%02d:%02d  •  เหรียญ %d  •  %s" % [hours, minutes, secs, coins, "กำลังถืออิฐ" if carried else "มือว่าง"]
	var destination := BUILD if carried else SUPPLY
	var to_target := (destination - player_position).normalized()
	var forward := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
	var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var front_score := forward.dot(to_target)
	var side_score := right.dot(to_target)
	var direction := "ข้างหน้า" if front_score >= 0 else "ข้างหลัง"
	if absf(side_score) > absf(front_score): direction = "ขวา" if side_score > 0 else "ซ้าย"
	hud_direction.text = "%s อยู่%s • เหลือ %.0f เมตร" % ["จุดก่อสร้าง" if carried else "กองอิฐ", direction, player_position.distance_to(destination)]
	if hint_time > 0.0:
		hud_prompt.text = hint
	elif placed == TOTAL:
		hud_prompt.text = "สร้างพีระมิดสำเร็จ! กด Esc เพื่อกลับเมนู"
	else:
		hud_prompt.text = "เมาส์: มอง  •  WASD / ลูกศร: เดิน  •  E / Space: หยิบหรือวาง" + ("  •  B: ร้าน" if mode == "normal" else "")
	for i in range(shop_buttons.size()):
		shop_buttons[i].disabled = upgrades[i] or coins < [25, 60, 110][i]
		if upgrades[i]: shop_buttons[i].text = ["รองเท้าเร็ว ✓", "รถเข็น ✓", "แผนที่ทางลัด ✓"][i]

func current_tier() -> int:
	var remaining := placed
	for tier in range(13):
		var count := (13 - tier) * (13 - tier)
		if remaining < count: return tier + 1
		remaining -= count
	return 13

func save_game() -> void:
	if mode == "": return
	var data := {"placed": placed, "carried": carried, "seconds": seconds_played, "coins": coins, "upgrades": upgrades, "player_x": player_position.x, "player_z": player_position.z}
	var file := FileAccess.open(SAVE_PREFIX + mode + ".json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(data))

func load_game() -> void:
	var path := SAVE_PREFIX + mode + ".json"
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: return
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return
	placed = clampi(int(data.get("placed", 0)), 0, TOTAL)
	carried = bool(data.get("carried", false)) and placed < TOTAL
	seconds_played = maxf(float(data.get("seconds", 0.0)), 0.0)
	coins = maxi(int(data.get("coins", 0)), 0)
	var saved_upgrades = data.get("upgrades", [false, false, false])
	if saved_upgrades is Array and saved_upgrades.size() == 3 and mode == "normal":
		for i in range(3): upgrades[i] = bool(saved_upgrades[i])
	player_position = Vector3(clampf(float(data.get("player_x", -18)), -55, 55), 0, clampf(float(data.get("player_z", 0)), -29, 29))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: save_game()
