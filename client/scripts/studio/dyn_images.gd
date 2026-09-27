class_name DynImages
extends RefCounted
## DynamicImage pictures ("dynimg://<id>"): one ImageTexture each, updated in place when
## a script draws, so every label, part and particle showing it changes along.

static var _textures := {}  # instance id -> ImageTexture


static func texture(id: String) -> ImageTexture:
	if not _textures.has(id):
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		_textures[id] = ImageTexture.create_from_image(img)
	return _textures[id]


## New pixels: base64 RGBA, width x height.
static func apply(id: String, w: int, h: int, data: String) -> void:
	var bytes := Marshalls.base64_to_raw(data)
	if w < 1 or h < 1 or bytes.size() != w * h * 4:
		return
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	var tex := texture(id)
	if tex.get_width() == w and tex.get_height() == h:
		tex.update(img)
	else:
		tex.set_image(img)


## A new place: nothing from the last one.
static func reset() -> void:
	_textures.clear()
