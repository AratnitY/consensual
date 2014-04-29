-- Usage:
-- Use the following two lines to load this file on some screen.
--   local menu_path= THEME:GetPathO("", "options_menu.lua")
--   dofile(menu_path)
-- Then declare whatever special menus you need inside the options_sets table
-- options_sets.menu and options_sets.special_functions are provided as
--   examples and for general use.
-- After declaring the specialized menus, call set_option_set_metatables().
-- Create a table with option_display_mt as the metatable.
-- option_display_mt follows my convention for actor wrappers of having
--   create_actors, find_actors, and name.
-- After calling option_display_mt.find_actors, call
--   option_display_mt.set_underline_color if you are going to use the
--   underline feature.
-- option_display_mt is not meant to be controlled directly, instead it is
--   meant to be given to a menu to control.  Control commands should be sent
--   to the menu, and the menu will take care of manipulating the display.
-- See ScreenSickPlayerOptions for a complicated example.

local move_time= 0.1
local underline_offset= 12
local underline_thickness= 2
local line_height= 24

local option_item_mt= {
	__index= {
		create_actors=
			function(self, name)
				self.name= name
				self.zoom= 1
				self.width= SCREEN_WIDTH
				return Def.ActorFrame{
					Name= name,
					normal_text("text", "", nil, nil, nil, self.zoom),
					Def.Quad{
						Name= "underline", InitCommand= cmd(y,underline_offset;horizalign,left;SetHeight,underline_thickness)
					}
				}
			end,
		find_actors=
			function(self, container)
				self.container= container
				self.text= container:GetChild("text")
				self.underline= container:GetChild("underline")
				self.underline:horizalign(center)
				return true
			end,
		set_geo=
			function(self, width, height, zoom)
				self.width= width
				self.zoom= zoom
				self.height= height
			end,
		set_underline_color=
			function(self, color)
				self.underline:diffuse(color)
			end,
		transform=
			function(self, item_index, num_items, is_focus)
				local changing_edge=
					((self.prev_index == 1 and item_index == num_items) or
				 (self.prev_index == num_items and item_index == 1))
				if changing_edge then
					self.container:diffusealpha(0)
				end
				self.container:finishtweening()
				self.container:linear(move_time)
				self.container:xy(0, (item_index - 1) *
												(self.height or self.text:GetZoomedHeight()))
				self.container:linear(move_time)
				self.container:diffusealpha(1)
				self.prev_index= item_index
			end,
		set=
			function(self, info)
				self.info= info
				if info then
					self:set_text(info.text)
					self:set_underline(info.underline)
				else
					self.text:settext("")
					self:set_underline(false)
				end
			end,
		set_underline=
			function(self, u)
				if u then
					self.underline:accelerate(0.25)
					self.underline:zoom(1)
				else
					self.underline:decelerate(0.25)
					self.underline:zoom(0)
				end
			end,
		set_text=
			function(self, t)
				self.text:settext(get_string_wrapper("OptionNames", t))
				width_limit_text(self.text, self.width, self.zoom)
				self.underline:SetWidth(self.text:GetZoomedWidth())
			end,
}}

option_display_mt= {
	__index= {
		create_actors=
			function(self, name, x, y, el_count, el_width, el_height, el_zoom, no_heading, no_display)
				self.name= name
				self.el_width= el_width or SCREEN_WIDTH
				self.el_height= el_height or 24
				self.el_zoom= el_zoom or 1
				self.no_heading= no_heading
				self.no_display= no_display
				local args= { Name= name, InitCommand= cmd(xy, x, y) }
				local next_y= 0
				if not no_heading then
					args[#args+1]= normal_text("heading", "")
					next_y= next_y + line_height
				end
				if not no_display then
					args[#args+1]= normal_text("display", "", nil, 0, line_height)
					next_y= next_y + line_height
				end
				if (not no_heading) or (not no_display) then
					next_y= next_y + line_height * .5
				end
				self.sick_wheel= setmetatable({disable_wrapping= true}, sick_wheel_mt)
				args[#args+1]= self.sick_wheel:create_actors(
					el_count, option_item_mt, 0, next_y)
				return Def.ActorFrame(args)
			end,
		find_actors=
			function(self, container)
				self.container= container
				if not self.no_heading then
					self.heading= container:GetChild("heading")
				end
				if not self.no_display then
					self.display= container:GetChild("display")
				end
				self.sick_wheel:find_actors(container:GetChild(self.sick_wheel.name))
				for i, item in ipairs(self.sick_wheel.items) do
					item:set_geo(self.el_width, self.el_height, self.el_zoom)
				end
			end,
		set_underline_color=
			function(self, color)
				for i, item in ipairs(self.sick_wheel.items) do
					item:set_underline_color(color)
				end
			end,
		set_heading=
			function(self, h)
				if not self.no_heading then
					self.heading:settext(get_string_wrapper("OptionTitles", h))
					width_limit_text(self.heading, self.el_width, self.el_zoom)
				end
			end,
		set_display=
			function(self, d)
				if not self.no_display then
					self.display:settext(d)
					width_limit_text(self.display, self.el_width, self.el_zoom)
				end
			end,
		set_info_set=
			function(self, info, pos)
				self.sick_wheel:set_info_set(info, pos or 1)
				self:unhide()
			end,
		set_element_info=
			function(self, element, info)
				self.sick_wheel:set_element_info(element, info)
			end,
		get_element=
			function(self, element)
				return self.sick_wheel:get_items_by_info_index(element)[1]
			end,
		scroll=
			function(self, pos)
				self.sick_wheel:scroll_to_pos(pos)
			end,
		hide=
			function(self) self.hidden= true self.container:diffusealpha(0) end,
		unhide=
			function(self) self.hidden= false self.container:diffusealpha(1) end
}}

function up_element()
	return {text= "<--"}
end

local option_set_general_mt= {
	__index= {
		set_player_info=
			function(self, player_number)
				self.player_number= player_number
			end,
		set_display=
			function(self, display)
				self.display= display
				display:set_info_set(self.info_set, self.cursor_pos)
				self:set_status()
			end,
		set_status= function() end, -- This is meant to be overridden.
		can_exit=
			function(self)
				return self.cursor_pos == 1
			end,
		get_cursor_element=
			function(self)
				if self.display then
					return self.display:get_element(self.cursor_pos)
				else
					return nil
				end
			end,
		interpret_code=
			function(self, code)
				local funs= {
					up= function(self)
								if self.cursor_pos > 1 then
									self.cursor_pos= self.cursor_pos - 1
								else
									self.cursor_pos= #self.info_set
								end
								self.display:scroll(self.cursor_pos)
								return true
							end,
					down= function(self)
									if self.cursor_pos < #self.info_set then
										self.cursor_pos= self.cursor_pos + 1
									else
										self.cursor_pos= 1
									end
									self.display:scroll(self.cursor_pos)
									return true
								end,
					start= function(self)
									 if self.info_set[self.cursor_pos].text ==
										 up_element().text then
										 -- This position is the "up" element that moves the
										 -- cursor back up the options tree.
										 return false
									 end
									 if self.interpret_start then
										 local hand, extra= self:interpret_start()
										 if self.scroll_to_move_on_start then
											 local pos_diff= 1 - self.cursor_pos
											 self.cursor_pos= 1
											 self.display:scroll(self.cursor_pos)
										 end
										 return hand, extra
									 else
										 return false
									 end
								 end
				}
				local cabinet_funs= {
					menu_left= funs.up, menu_right= funs.down, start= funs.start
				}
				local use_funs= funs
				if get_input_mode() == input_mode_cabinet then
					use_funs= cabinet_funs
				end
				if use_funs[code] then return use_funs[code](self) end
				return false
			end
}}

options_sets= {}

-- MENU ENTRIES STRUCTURE
-- {}
--   name= string -- Name for the entry
--   args= {} -- Args to return to options_menu_mt to construct the new menu
--     meta= {} -- metatable for the submenu
--     args= {} -- extra args for the initialize function of the metatable
options_sets.menu= {
	__index= {
		initialize=
			function(self, player_number, initializer_args, no_up)
				self.menu_data= initializer_args
				self.name= initializer_args.name
				self.info_set= {}
				self.no_up= no_up
				if not no_up then
					self.info_set[#self.info_set+1]= up_element()
				end
				self.cursor_pos= 1
				for i, d in ipairs(initializer_args) do
					self.info_set[#self.info_set+1]= {text= d.name}
					if d.args and type(d.args) == "table" then
						d.args.name= d.name
					end
				end
			end,
		set_status=
			function(self)
				if self.display then
					self.display:set_heading(self.name or "")
					self.display:set_display("")
				end
			end,
		interpret_start=
			function(self)
				local data= self.menu_data[self.cursor_pos-1]
				if self.no_up then
					data= self.menu_data[self.cursor_pos]
				end
				if data then
					return true, data
				else
					Trace("options_sets.menu has no data at " .. self.cursor_pos-1)
					rec_print_table(self.menu_data)
					return false
				end
			end
}}

options_sets.special_functions= {
	-- element_set structure:
	-- element_set= {}
	--   {} -- info for one element
	--     name -- string for naming the element.
	--     init(player_number) -- called to init the element, returns bool.
	--     set(player_number) -- called when the element is set.
	--     unset(player_number) -- called when the element is unset.
	__index= {
		initialize=
			function(self, player_number, extra)
				self.name= extra.name
				self.cursor_pos= 1
				self.player_number= player_number
				self.element_set= extra.eles
				self.info_set= {up_element()}
				for i, el in ipairs(self.element_set) do
					self.info_set[#self.info_set+1]= {
						text= el.name, underline= el.init(player_number)}
				end
			end,
		set_status= function(self) self.display:set_heading(self.name) end,
		interpret_start=
			function(self)
				local ele_pos= self.cursor_pos - 1
				local ele_info= self.element_set[ele_pos]
				if ele_info then
					local is_info= self.info_set[self.cursor_pos]
					if is_info.underline then
						ele_info.unset(self.player_number)
					else
						ele_info.set(self.player_number)
					end
					is_info.underline= not is_info.underline
					self.display:set_element_info(self.cursor_pos, is_info)
					return true
				else
					return false
				end
			end
}}

options_sets.mutually_exclusive_special_functions= {
	__index= {
		initialize= options_sets.special_functions.__index.initialize,
		set_status= options_sets.special_functions.__index.set_status,
		interpret_start=
			function(self)
				local ret= options_sets.special_functions.__index.interpret_start(self)
				if ret then
					for i, info in ipairs(self.info_set) do
						if i ~= self.cursor_pos then
							if info.underline then
								info.underline= false
								self.display:set_element_info(i, info)
							end
						end
					end
				end
				return ret
			end
}}

options_sets.adjustable_float= {
	__index= {
		initialize=
			function(self, player_number, extra)
				local function check_member(member_name)
					if not self[member_name] then
						error("adjustable_float '" .. self.name .. "' warning: " ..
									member_name .. " not provided.")
					end
				end
				Trace("adjustable_float extra:")
				rec_print_table(extra)
				self.name= extra.name
				self.cursor_pos= 1
				self.player_number= player_number
				self.min_scale= extra.min_scale
				self.scale= extra.scale or 1
				self.min_scale_used= self.scale
				self.current_value= extra.initial_value(player_number)
				if self.current_value ~= 0 then
					local cv_scale= 10^math.floor(math.log(math.abs(self.current_value)) / math.log(10))
					if self.min_scale then
						cv_scale= math.max(self.min_scale, cv_scale)
					end
					if self.max_scale then
						cv_scale= math.min(cv_scale, self.max_scale)
					end
					self.min_scale_used= math.min(cv_scale, self.scale)
				end
				self.max_scale= extra.max_scale
				self.set= extra.set
				check_member("set")
				self.validator= extra.validator or noop_true
				self.val_to_text= extra.val_to_text
				check_member("val_to_text")
				local scale_text= get_string_wrapper("OptionNames", "scale")
				self.info_set= {
					up_element(), {text= "+"..self.scale}, {text= "-"..self.scale},
					{text= scale_text.."*10"}, {text= scale_text.."/10"}}
			end,
		interpret_start=
			function(self)
				if self.cursor_pos == 2 then
					self:set_new_val(self.current_value + self.scale)
					return true
				elseif self.cursor_pos == 3 then
					self:set_new_val(self.current_value - self.scale)
					return true
				elseif self.cursor_pos == 4 then
					self:set_new_scale(self.scale * 10)
					return true
				elseif self.cursor_pos == 5 then
					self:set_new_scale(self.scale / 10)
					return true
				else
					return false
				end
			end,
		set_status=
			function(self)
				if self.display then
					self.display:set_heading(self.name)
					self.display:set_display(self.val_to_text(self.current_value))
				end
			end,
		set_new_val=
			function(self, nval)
				local min_scale_log= math.floor(math.log10(self.min_scale_used))
				local raise= 10^-min_scale_log
				local lower= 10^min_scale_log
				local rounded_val= math.floor(nval * raise) * lower
				if self.validator(rounded_val) then
					self.current_value= rounded_val
					self.set(self.player_number, rounded_val)
					self.display:set_display(self.val_to_text(rounded_val))
				end
			end,
		set_new_scale=
			function(self, nscale)
				nscale= pow_ten_force(nscale)
				local valid= gte_nil(nscale, self.min_scale) and lte_nil(nscale, self.max_scale)
				if valid then
					self.min_scale_used= math.min(nscale, self.min_scale_used)
					self.scale= nscale
					self.info_set[2].text= "+" .. nscale
					self.info_set[3].text= "-" .. nscale
					self.display:set_element_info(2, self.info_set[2])
					self.display:set_element_info(3, self.info_set[3])
				end
			end
}}

function set_option_set_metatables()
	for k, set in pairs(options_sets) do
		setmetatable(set.__index, option_set_general_mt)
	end
end
