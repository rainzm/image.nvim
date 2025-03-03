---@meta

---@class API
---@field setup fun(options?: Options)
---@field from_file fun(path: string, options?: ImageOptions): Image
---@field from_url fun(url: string, options?: ImageOptions, callback: fun(image: Image|nil))
---@field clear fun(id?: string)
---@field get_images fun(opts?: { window?: number, buffer?: number }): Image[]

---@class State
---@field backend Backend
---@field options Options
---@field images { [string]: Image }
---@field extmarks_namespace any
---@field remote_cache { [string]: string }
---@field tmp_dir string

---@class DocumentIntegrationOptions
---@field enabled? boolean
---@field download_remote_images? boolean
---@field clear_in_insert_mode? boolean
---@field only_render_image_at_cursor? boolean
---@field filetypes? string[]

---@alias IntegrationOptions DocumentIntegrationOptions

---@class Options
---@field backend "kitty"|"ueberzug"
---@field integrations table<string, IntegrationOptions>
---@field max_width? number
---@field max_height? number
---@field max_width_window_percentage? number
---@field max_height_window_percentage? number
---@field kitty_method "normal"|"unicode-placeholders"
---@field window_overlap_clear_enabled? boolean
---@field window_overlap_clear_ft_ignore? string[]

---@class BackendFeatures
---@field crop boolean

---@class Backend
---@field state State
---@field features BackendFeatures
---@field setup fun(state: State)
---@field render fun(image: Image, x: number, y: number, width?: number, height?: number)
---@field clear fun(id?: string, shallow?: boolean)

---@class ImageGeometry
---@field x? number
---@field y? number
---@field width? number
---@field height? number

---@class ImageOptions: ImageGeometry
---@field id? string
---@field window? number
---@field buffer? number
---@field with_virtual_padding? boolean

---@class ImageBounds
---@field top number
---@field right number
---@field bottom number
---@field left number

---@class MagickImage
---@field adaptive_resize fun(self: MagickImage, width: number, height: number)
---@field clone fun(self: MagickImage): MagickImage
---@field composite fun(self: MagickImage, source: MagickImage, x: number, y: number, operator?: string)
---@field crop fun(self: MagickImage, width: number, height: number, x?: number, y?: number)
---@field destroy fun(self: MagickImage)
---@field get_format fun(self: MagickImage): string
---@field get_height fun(self: MagickImage): number
---@field get_width fun(self: MagickImage): number
---@field modulate fun(self: MagickImage, brightness?: number, saturation?: number, hue?: number)
---@field resize fun(self: MagickImage, width: number, height: number)
---@field resize_and_crop fun(self: MagickImage, width: number, height: number)
---@field scale fun(self: MagickImage, width: number, height: number)
---@field set_format fun(self: MagickImage, format: string)
---@field write fun(self: MagickImage, path: string)

---@class Image
---@field id string
---@field internal_id number
---@field path string
---@field resized_path string
---@field cropped_path string
---@field original_path string
---@field image_width number
---@field image_height number
---@field window? number
---@field buffer? number
---@field with_virtual_padding? boolean
---@field geometry ImageGeometry
---@field rendered_geometry ImageGeometry
---@field bounds ImageBounds
---@field is_rendered boolean
---@field resize_hash? string
---@field crop_hash? string
---@field global_state State
---@field render fun(self: Image, geometry?: ImageGeometry)
---@field clear fun(self: Image, shallow?: boolean)
---@field move fun(self: Image, x: number, y: number)
---@field brightness fun(self: Image, brightness: number)
---@field saturation fun(self: Image, saturation: number)
---@field hue fun(self: Image, hue: number)

-- wish proper generics were a thing here
---@class IntegrationContext
---@field api API
---@field options IntegrationOptions
---@field state State

---@class Integration
---@field setup? fun(api: API, options: IntegrationOptions, state: State)

---@class Window
---@field id number
---@field buffer number
---@field buffer_filetype string
---@field buffer_is_listed boolean
---@field x number
---@field y number
---@field width number
---@field height number
---@field scroll_x number
---@field scroll_y number
---@field is_visible boolean
---@field is_normal boolean
---@field is_floating boolean
---@field zindex number
---@field rect { top: number, right: number, bottom: number, left: number }
---@field masks { x: number, y: number, width: number, height: number }[]

---@class KittyControlConfig
---@field action "t"|"T"|"p"|"d"|"f"|"c"|"a"|"q"
---@field image_id? string|number
---@field image_number? number
---@field placement_id? string|number
---@field quiet? 0|1|2
---@field transmit_format? 32|24|100
---@field transmit_medium? "d"|"f"|"t"|"s"
---@field transmit_more? 0|1
---@field transmit_width? number
---@field transmit_height? number
---@field transmit_file_size? number
---@field transmit_file_offset? number
---@field transmit_compression? 0|1
---@field display_x? number
---@field display_y? number
---@field display_width? number
---@field display_height? number
---@field display_x_offset? number
---@field display_y_offset? number
---@field display_columns? number
---@field display_rows? number
---@field display_cursor_policy? 0|1
---@field display_virtual_placeholder? 0|1
---@field display_zindex? number
---@field display_delete? "a"|"A"|"i"|"I"|"p"
