local line_height= 24
local option_set_elements= (SCREEN_HEIGHT / line_height) - 5
local sect_width= SCREEN_WIDTH/2
local sect_height= SCREEN_HEIGHT

-- SPEED RATE COORDINATION
-- Each speed option row and each rate mod option line registers with this
-- structure so they can coordinate their displayed values.  This is
-- important because the speed mod is effectively multiplied by the rate mod.
--
-- add_to_notify(line)
--   Adds line to a list of things that will be notified when the rate
--     changes.  line must have a function named "notify_of_rate_change" that
--     takes no arguments.
--
-- notify_of_rate_change(new_rate)
--   Notifies all things in the list of the rate change.  Things that change
--     the rate should call this function.
--
-- get_current_rate()
--   Returns the current rate.

local rate_coordinator= setmetatable({}, rate_coordinator_interface_mt)
rate_coordinator:initialize()
-- The current rate is a leftover from the previous song.  It might slow the
-- current song down enough to go over the time limit.  So it needs to be
-- adjusted to bring the song within that limit.
if GAMESTATE:GetCoinMode() ~= "CoinMode_Home" then
	local remain= get_time_remaining()
	local song_len= get_current_song_length()
	local rate= rate_coordinator:get_current_rate()
	if song_len / rate > remain then
		local new_rate= song_len / remain
		new_rate= force_to_range(0.5, new_rate, 2.0)
		new_rate= math.round(new_rate * 100) / 100
		GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate(new_rate)
		rate_coordinator:notify(new_rate, true)
	end
end

local function mod_player(pn, mod_name, value)
	local mod_func= PlayerOptions[mod_name]
	if mod_func then
		return mod_func(cons_players[pn].preferred_options, value)
	else
		Warn("mod '" .. tostring(mod_name) .. "' does not exist.")
	end
end

local profiles= {}
for i, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	profiles[pn]= PROFILEMAN:GetProfile(pn)
end

local bpm_displayer_interface= {}
local bpm_displayer_interface_mt= { __index= bpm_displayer_interface }
function bpm_displayer_interface:create_actors(name, player_number, x, y)
	self.name= name
	self.player_number= player_number
	rate_coordinator:add_to_notify(self)
	local bpm_text= self:bpm_text()
	local args= {
		Name=name,
		InitCommand= function(subself)
			self.container= subself
			subself:xy(x, y)
		end
	}
	self.tani= setmetatable({}, text_and_number_interface_mt)
	args[#args+1]= self.tani:create_actors(
		"itani", { tx= -4, nx= 4, tt= "BPM", nt= bpm_text })
	return Def.ActorFrame(args)
end

function bpm_displayer_interface:bpm_text()
	local bpm_text= ""
	local short_text= ""
	local steps= gamestate_get_curr_steps(self.player_number)
	if steps then
		local bpms= steps_get_bpms(steps)
		local curr_rate= rate_coordinator:get_current_rate()
		local low, high= false, false
		for i, v in ipairs(bpms) do
			if not low or v < low then
				low= v
			end
			if not high or v > high then
				high= v
			end
			if i > 1 then
				bpm_text= bpm_text .. "-"
			end
			bpm_text= bpm_text .. ("%.0f"):format(v * curr_rate)
		end
		short_text= ("%.0f"):format(low * curr_rate)
		if low ~= high then
			short_text= short_text .. "-" .. ("%.0f"):format(high * curr_rate)
		end
	end
	return short_text
end

function bpm_displayer_interface:notify_of_rate_change()
	if self.container then
		self.tani:set_number(self:bpm_text())
	end
end

dofile(THEME:GetPathO("", "options_menu.lua"))

local speed_inc_base= 25
local speed_inc_base_recip= 1/speed_inc_base

options_sets.speed= {
	__index= {
		initialize=
			function(self, player_number)
				self.info_set= {
					up_element(), {text= ""}, {text= ""}, {text= ""}, {text= ""},
					{text= "Xmod"}, {text= "Cmod"}, {text= "Mmod"},
					{text= "CXmod"}, {text= "Driven"}, {text= "Alt Driven"}
				}
				local speed_info= cons_players[player_number]:get_speed_info()
				self.current_speed= speed_info.speed
				self:set_mode_data_work(speed_info.mode)
				self.cursor_pos= 1
			end,
		set_status=
			function(self)
				self.display:set_heading("Speed")
				self:update_speed_text()
			end,
		set_player_speed_info=
			function(self)
				local spi= cons_players[self.player_number].speed_info
				spi.mode= self.mode
				spi.speed= self.current_speed
			end,
		update_speed_text=
			function(self)
				if self.display then
					local form_speed= ("%.2f"):format(self.current_speed)
					if self.mode == "x" then
						self.display:set_display(form_speed .. "x")
					elseif self.mode == "D" and cons_players[self.player_number].dspeed.alternate then
						self.display:set_display(self.mode .. "A" .. form_speed)
					else
						self.display:set_display(self.mode .. form_speed)
					end
				end
			end,
		inc_lock_speed=
			function(self, mode, speed)
				if mode == "x" then
					return (math.round((speed * 100) * speed_inc_base_recip) * speed_inc_base) * .01
				else
					return math.round(speed * speed_inc_base_recip) * speed_inc_base
				end
			end,
		set_mode_data_work=
			function(self, new_mode)
				local function get_song_speed()
					--Trace("Speed pn: " .. tostring(self.player_number))
					local bpms= steps_get_bpms(gamestate_get_curr_steps(self.player_number))
					-- A song will only have 1 or 2 bpms, depending on how its
					-- displaybpm is set.
					-- A course probably has more than one bpm.
					-- This is a placeholder until I fix TimingData.GetBPMsAndTimes to
					-- not return strings.
					if #bpms > 2 then
						return bpms[1]
					else
						return bpms[2] or bpms[1]
					end
				end
				if new_mode == "x" then
					-- You might think this is redundant, because "of course the current mode isn't x", but set_mode_data_work is also used in initializing.
					if self.mode and self.mode ~= "x" then
						self.current_speed= self.current_speed / get_song_speed()
						self.current_speed= self:inc_lock_speed("x", self.current_speed)
					end
				else
					if self.mode == "x" then
						self.current_speed= self.current_speed * get_song_speed()
						self.current_speed= self:inc_lock_speed("m", self.current_speed)
					end
				end
				local bi= 1
				if new_mode == "x" then
					bi= speed_inc_base * .01
				else
					bi= speed_inc_base
				end
				self.info_set[2].text= "+" .. (bi * 4)
				self.info_set[3].text= "+" .. bi
				self.info_set[4].text= "" .. (bi * -1)
				self.info_set[5].text= "" .. (bi * -4)
				if self.display then
					for i= 2, 5 do
						self.display:set_element_info(i, self.info_set[i])
					end
				end
				self.mode= new_mode
				self:update_speed_text()
			end,
		set_mode=
			function(self, new_mode)
				if new_mode == self.mode then return end
				if not new_mode then
					Trace("options_sets.speed.set_mode:  Attempted to set nil mode")
					return
				end
				if new_mode ~= "m" and new_mode ~= "x" and new_mode ~= "C"
				and new_mode ~= "CX" and new_mode ~= "D" then
					Trace("options_sets.speed.set_mode:  Attempted to set invalid mode " .. new_mode)
					return
				end
				self:set_mode_data_work(new_mode)
				self:set_player_speed_info()
				--Trace(self.player_number .. " speed info:")
				--rec_print_table(cons_players[self.player_number].speed_info)
			end,
		interpret_start=
			function(self)
				local cp= self.cursor_pos
				if cp == 6 then
					self:set_mode("x")
				elseif cp == 7 then
					self:set_mode("C")
				elseif cp == 8 then
					self:set_mode("m")
				elseif cp == 9 then
					self:set_mode("CX")
				elseif cp == 10 then
					self:set_mode("D")
					if not cons_players[self.player_number].dspeed then
						cons_players[self.player_number].dspeed= {min= dspeed_default_min, max= dspeed_default_max, alternate= false}
					end
					cons_players[self.player_number].dspeed.alternate= false
				elseif cp == 11 then
					self:set_mode("D")
					if not cons_players[self.player_number].dspeed then
						cons_players[self.player_number].dspeed= {min= dspeed_default_min, max= dspeed_default_max, alternate= false}
					end
					cons_players[self.player_number].dspeed.alternate= true
				elseif self.info_set[cp] then
					self.current_speed=
						self:inc_lock_speed(
						self.mode, self.current_speed + tonumber(self.info_set[cp].text))
					self:update_speed_text()
					self:set_player_speed_info()
					--Trace(self.player_number .. " speed info:")
					--rec_print_table(cons_players[self.player_number].speed_info)
				end
				return true
			end,
}}

options_sets.assorted_bools= {
	__index= {
		initialize=
			function(self, player_number, extra)
				self.player_number= player_number
				self.name= extra.name
				self.info_set= {up_element()}
				self.ops= self.ops or {}
				for i, op in ipairs(extra.ops) do
					local opsind= #self.ops+1
					self.ops[opsind]= op
					local is_set= mod_player(self.player_number, op)
					self.info_set[#self.info_set+1]= {text= op, underline= is_set}
				end
				self.cursor_pos= 1
			end,
		set_status=
			function(self)
				self.display:set_heading(self.name)
				self.display:set_display("")
			end,
		interpret_start=
			function(self)
				local ops_pos= self.cursor_pos - 1
				local info= self.info_set[self.cursor_pos]
				if self.ops[ops_pos] then
					if info.underline then
						mod_player(self.player_number, self.ops[ops_pos], false)
					else
						mod_player(self.player_number, self.ops[ops_pos], true)
					end
					info.underline= not info.underline
					self.display:set_element_info(self.cursor_pos, info)
					return true
				else
					return false
				end
			end
}}

options_sets.song_ops_bools= {
	__index= {
		initialize=
			function(self, player_number, extra)
				self.player_number= player_number
				self.name= extra.name
				self.info_set= {up_element()}
				self.ops= self.ops or {}
				local songops= GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
				for i, op in ipairs(extra.ops) do
					local opsind= #self.ops+1
					self.ops[opsind]= op
					local is_set= songops[op](songops)
					self.info_set[#self.info_set+1]= {text= op, underline= is_set}
				end
				self.cursor_pos= 1
			end,
		set_status=
			function(self)
				self.display:set_heading(self.name)
				self.display:set_display("")
			end,
		interpret_start=
			function(self)
				local ops_pos= self.cursor_pos - 1
				local info= self.info_set[self.cursor_pos]
				local songops= GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
				if self.ops[ops_pos] then
					if info.underline then
						songops[self.ops[ops_pos]](songops, false)
					else
						songops[self.ops[ops_pos]](songops, true)
					end
					info.underline= not info.underline
					self.display:set_element_info(self.cursor_pos, info)
					return true
				else
					return false
				end
			end
}}

options_sets.mutually_exclusive_bools= {
-- Relies on the engine to enforce the mutual exclusivity.
-- Reuse functions from options_rows.assorted_bools that would be identical.
	__index= {
		initialize= options_sets.assorted_bools.__index.initialize,
		set_status= options_sets.assorted_bools.__index.set_status,
		interpret_start=
			function(self)
				local ops_pos= self.cursor_pos - 1
				local info= self.info_set[self.cursor_pos]
				if self.ops[ops_pos] then
					if info.underline then
						if not self.disallow_unset then
							info.underline= false
							mod_player(self.player_number, self.ops[ops_pos], false)
							self.display:set_element_info(self.cursor_pos, info)
						end
					else
						for i, tinfo in ipairs(self.info_set) do
							if tinfo ~= info then
								tinfo.underline= false
							else
								tinfo.underline= true
							end
							self.display:set_element_info(i, tinfo)
						end
						mod_player(self.player_number, self.ops[ops_pos], true)
					end
					return true
				else
					return false
				end
			end,
}}

options_sets.rate_mod= {
	__index= {
		initialize=
			function(self, player_number, extra)
				self.player_number= player_number
				self.cursor_pos= 1
				self.name= extra.name
				self.info_set= {up_element()}
				self.increments= {}
				self.current_value= rate_coordinator:get_current_rate()
				for i, v in ipairs(extra.incs) do
					self.increments[i]= v
					local vt= tostring(v)
					if v > 0 then vt= "+" .. vt end
					self.info_set[#self.info_set+1]= {text= vt}
				end
				self.info_set[#self.info_set+1]= {text= "Reset"}
				rate_coordinator:add_to_notify(self)
			end,
		destructor=
			function(self)
				rate_coordinator:remove_from_notify(self)
			end,
		set_status=
			function(self)
				self.display:set_heading(self.name)
				self.display:set_display(self:get_eltext())
			end,
		interpret_start=
			function(self)
				local incs_pos= self.cursor_pos - 1
				if self.increments[incs_pos] then
					self:set_new_val(self.current_value + self.increments[incs_pos])
					return true
				elseif self.cursor_pos == #self.info_set then
					self:set_new_val(1)
					return true
				else
					return false
				end
			end,
		set_new_val=
			function(self, nval)
				if nval == -0 then nval= 0 end
				if self:valid_value(nval) then
					self.current_value= nval
				end
				self.display:set_display(self:get_eltext())
				self:mod_command()
				rate_coordinator:notify(self.current_value, true)
			end,
		get_eltext= function(self) return self.current_value .. "x" end,
		mod_command=
			function(self)
				GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):MusicRate(self.current_value)
			end,
		valid_value=
			function(self, value)
				if value <= 0.499 or value > 2.001 then return false end
				if GAMESTATE:GetCoinMode() == "CoinMode_Home" then return true end
				local modified_length= get_current_song_length() / value
				return modified_length <= get_time_remaining()
			end,
		notify_of_rate_change=
			function(self)
				self.current_value= rate_coordinator:get_current_rate()
				self.display:set_display(self:get_eltext())
			end
}}

options_sets.steps_list= {
	__index= {
		initialize=
			function(self, player_number)
				self.cursor_pos= 1
				self.player_number= player_number
				self.steps_list= get_filtered_sorted_steps_list()
				if not self.steps_list or #self.steps_list < 1 then
					Trace("Could not get steps_list.")
					return
				end
				self.info_set= {up_element()}
				for i, st in ipairs(self.steps_list) do
					self.info_set[#self.info_set+1]=
						{text= self:get_steps_string(st), underline= false}
				end
				local steps= gamestate_get_curr_steps(player_number)
				if steps then
					for i, st in ipairs(self.steps_list) do
						if steps == st then
							self.player_choice= i
							self.info_set[i+1].underline= true
							break
						end
					end
				else
					Trace("GetCurrentSteps returned nil dude.")
				end
				if not self.player_choice then
					Trace("Somehow, the player hasn't picked a difficulty.")
					self.player_choice= 1
				end
			end,
		set_status=
			function(self)
				self.display:set_heading("Steps")
				self.display:set_display(self:get_steps_string())
			end,
		get_steps_string=
			function(self, steps)
				steps= steps or self.steps_list[self.player_choice]
				return steps_to_string(steps) .. " " .. steps:GetMeter()
			end,
		interpret_start=
			function(self)
				local spos= self.cursor_pos - 1
				local steps= self.steps_list[spos]
				if steps then
					cons_set_current_steps(self.player_number, steps)
					local steps_info= self.info_set[self.player_choice+1]
					steps_info.underline= false
					self.display:set_element_info(self.player_choice+1, steps_info)
					self.player_choice= spos
					-- Note the line above updating player_choice.
					steps_info= self.info_set[self.player_choice+1]
					steps_info.underline= true
					self.display:set_element_info(self.player_choice+1, steps_info)
					return true
				else
					return false
				end
			end
}}

options_sets.noteskins= {
	__index= {
		disallow_unset= true,
		scroll_to_move_on_start= true,
		initialize=
			function(self, player_number)
				self.player_number= player_number
				self.cursor_pos= 1
				self.ops= NOTESKIN:GetNoteSkinNames()
				local player_noteskin= mod_player(self.player_number, "NoteSkin")
				function find_matching_noteskin()
					for ni, nv in ipairs(self.ops) do
						Trace("Noteskin found: '" .. tostring(nv) .. "'")
						if player_noteskin == nv then
							return ni
						end
					end
					return nil
				end
				self.selected_skin= find_matching_noteskin()
				self.info_set= {up_element()}
				for ni, nv in ipairs(self.ops) do
					self.info_set[#self.info_set+1]= {
						text= nv, underline= ni == self.selected_skin}
				end
			end,
		interpret_start=
			function(self)
				local ops_pos= self.cursor_pos - 1
				local info= self.info_set[self.cursor_pos]
				if self.ops[ops_pos] then
					for i, tinfo in ipairs(self.info_set) do
						if i ~= self.cursor_pos and tinfo.underline then
							tinfo.underline= false
							self.display:set_element_info(i, tinfo)
						end
					end
					local prev_note, succeeded= mod_player(self.player_number, "NoteSkin", self.ops[ops_pos])
					if not succeeded then
						Trace("Failed to set noteskin '" .. tostring(self.ops[ops_pos]) .. "'.  Leaving noteskin setting at '" .. prev_note .. "'")
					end
					info.underline= true
					self.display:set_element_info(self.cursor_pos, info)
					self:set_status()
					return true
				else
					return false
				end
			end,
		set_status=
			function(self)
				self.display:set_heading("Noteskin")
				self.display:set_display(mod_player(self.player_number, "NoteSkin"))
			end
}}

dofile(THEME:GetPathO("", "tags_menu.lua"))

set_option_set_metatables()

local function set_clear_for_player(player_number)
	if true then
		Trace("Clear option disabled until partial clear of player data is added.")
		return
	end
	GAMESTATE:ApplyGameCommand("mod,clearall", player_number)
	-- SM5 will crash if a noteskin is not applied after clearing all mods.
	-- Apply the default noteskin first in case Cel doesn't exist.
	local default_noteskin= THEME:GetMetric("Common", "DefaultNoteSkinName")
	local prev_note, succeeded= self.song_options:NoteSkin("uswcelsm5")
	if not succeeded then
		prev_note, succeeded= self.song_options:NoteSkin(default_noteskin)
		if not succeeded then
			Warn("Failed to set default noteskin when clearing player options.  Please do not delete the default noteskin.")
		end
	end
end

local function generic_fake_judge_element(judge_name)
	return {name= judge_name, init= check_fake_judge(judge_name),
					set= set_fake_judge(judge_name), unset= unset_fake_judge}
end

local function generic_mine_effect_element(name)
	return {name= name, init= check_mine_effect(name),
					set= set_mine_effect(name), unset= unset_mine_effect}
end

local function extra_for_adj_float_mod(mod_name, is_angle)
	return {
		name= mod_name,
		min_scale= -4,
		scale= -1,
		max_scale= 1,
		is_angle= is_angle,
		initial_value=
			function(player_number)
				return mod_player(player_number, mod_name)
			end,
		set=
			function(player_number, value)
				mod_player(player_number, mod_name, value)
			end,
		scale_to_text=
			function(player_number, value)
				if cons_players[player_number].flags.interface.straight_floats then
					return value
				else
					return value * 100
				end
			end,
		val_to_text=
			function(player_number, value)
				if cons_players[player_number].flags.interface.straight_floats then
					if value == -0 then return "0" end
					return tostring(value)
				else
					if value == -0 then return "0%" end
					return (value * 100) .. "%"
				end
			end
	}
end

local function extra_for_dspeed_min(name)
	local receptor_min= THEME:GetMetric("Player", "ReceptorArrowsYStandard")
	local receptor_max= THEME:GetMetric("Player", "ReceptorArrowsYReverse")
	local arrow_height= THEME:GetMetric("ArrowEffects", "ArrowSpacing")
	local field_height= receptor_max - receptor_min
	local center_effect_size= field_height / 2
	return {
		name= name,
		min_scale= -4,
		scale= -1,
		max_scale= 1,
		reset_value= (SCREEN_CENTER_Y + receptor_min) / -center_effect_size,
		initial_value=
			function(player_number)
				return cons_players[player_number].dspeed.min
			end,
		set=
			function(player_number, value)
				cons_players[player_number].dspeed.min= value
			end,
	}
end

local function extra_for_dspeed_max(name)
	local receptor_min= THEME:GetMetric("Player", "ReceptorArrowsYStandard")
	local receptor_max= THEME:GetMetric("Player", "ReceptorArrowsYReverse")
	local arrow_height= THEME:GetMetric("ArrowEffects", "ArrowSpacing")
	local field_height= receptor_max - receptor_min
	local center_effect_size= field_height / 2
	return {
		name= name,
		min_scale= -4,
		scale= -1,
		max_scale= 1,
		reset_value= (SCREEN_CENTER_Y + receptor_max) / center_effect_size,
		initial_value=
			function(player_number)
				return cons_players[player_number].dspeed.max
			end,
		set=
			function(player_number, value)
				cons_players[player_number].dspeed.max= value
			end,
	}
end

local function extra_for_sigil_detail()
	return {
		name= "Sigil Detail",
		min_scale= 0,
		scale= 0,
		max_scale= 1,
		initial_value=
			function(player_number)
				return cons_players[player_number].sigil_data.detail
			end,
		validator=
			function(value)
				return value >= 1 and value <= 32
			end,
		set=
			function(player_number, value)
				cons_players[player_number].sigil_data.detail= value
			end,
	}
end

local function extra_for_sigil_size()
	return {
		name= "Sigil Size",
		min_scale= 0,
		scale= 1,
		max_scale= 2,
		initial_value=
			function(player_number)
				return cons_players[player_number].sigil_data.size
			end,
		validator=
			function(value)
				return value >= 1 and value <= SCREEN_WIDTH/2
			end,
		set=
			function(player_number, value)
				cons_players[player_number].sigil_data.size= value
			end,
	}
end

local function extra_for_sideswap()
	return {
		name= "Side Swap",
		min_scale= -2,
		scale= 0,
		max_scale= 0,
		initial_value= function(player_number)
			return cons_players[player_number].side_swap or 0
		end,
		validator= noop_true,
		set= function(player_number, value)
			cons_players[player_number].side_swap= value
		end
	}
end

local function extra_for_lives()
	return {
		name= "Battery Lives",
		min_scale= 0,
		scale= 0,
		max_scale= 4,
		initial_value=
			function(player_number)
				return mod_player(player_number, "BatteryLives")
			end,
		validator=
			function(value)
				return value >= 1
			end,
		set=
			function(player_number, value)
				mod_player(player_number, "BatteryLives", value)
			end
	}
end

local function extra_for_haste()
	return {
		name= "Haste",
		min_scale= -2,
		scale= 0,
		max_scale= 0,
		initial_value=
			function(player_number)
				return GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):Haste()
			end,
		validator=
			function(value)
				return value >= -1 and value <= 1
			end,
		set=
			function(player_number, value)
				GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred"):Haste(value)
			end
	}
end

local function make_profile_float_extra(func_name)
	return {
		name= func_name,
		min_scale= 0,
		scale= 0,
		max_scale= 3,
		initial_value= function(pn)
			if profiles[pn] then
				return profiles[pn]["Get"..func_name](profiles[pn])
			end
			return 0
		end,
		set= function(pn, val)
			if profiles[pn] then
				profiles[pn]["Set"..func_name](profiles[pn], val)
			end
		end,
		validator= function(val)
			return val >= 0
		end
	}
end

local function make_profile_bool_extra(name, true_text, false_text, func_name)
	return {
		true_text= true_text, false_text= false_text,
		get= function(pn)
			if profiles[pn] then
				return profiles[pn]["Get"..func_name](profiles[pn])
			end
			return false
		end,
		set= function(pn, val)
			if profiles[pn] then
				profiles[pn]["Set"..func_name](profiles[pn], val)
			end
		end
	}
end

local function make_menu_of_float_set(float_set, is_angle)
	local margs= {}
	for i, fl in ipairs(float_set) do
		margs[#margs+1]= {
			name= fl, meta= options_sets.adjustable_float,
			args= extra_for_adj_float_mod(fl, is_angle)
		}
	end
	return margs
end

local function ass_bools(name, bool_names)
	return {
		name= name, meta= options_sets.assorted_bools, args= {ops= bool_names}}
end

local function song_bools(name, bool_names)
	return {
		name= name, meta= options_sets.song_ops_bools, args= {ops= bool_names}}
end

local function pops_get(pn)
	return GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred")
end

local function player_enum(name, enum, func_name)
	-- We need to inform GameState if we set the fail type so it doesn't
	-- override it with the beginner/easy preferences.
	local function set_wrapper(obj, val)
		if GAMESTATE.SetFailTypeExplicitlySet then
			GAMESTATE:SetFailTypeExplicitlySet()
		end
		PlayerOptions[func_name](obj, val)
	end
	local set= PlayerOptions[func_name]
	if func_name == "FailSetting" then
		set= set_wrapper
	end
	return {
		name= name, meta= options_sets.enum_option, args= {
			get= PlayerOptions[func_name], set= set,
			enum= enum, obj_get= pops_get }}
end

local function song_enum(name, enum, func_name)
	return {
		name= name, meta= options_sets.enum_option, args= {
			get= SongOptions[func_name], set= SongOptions[func_name], enum= enum,
			obj_get= function() return GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred") end }}
end

local function mut_exc_bools(name, bool_names)
	return {
		name= name, meta= options_sets.mutually_exclusive_bools, args= {ops= bool_names}}
end

local args= {}
local menus= {}
local bpm_disps= {}
local frames= {}
for i, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local menu= setmetatable({}, menu_stack_mt)
	local bpm= setmetatable({}, bpm_displayer_interface_mt)
	local frame= setmetatable({}, frame_helper_mt)
	local mx, my= 0, 0
	if pn == PLAYER_2 then
		mx= sect_width
	end
	local pcolor= solar_colors[pn]()
	local pname= pn
	local pro= PROFILEMAN:GetProfile(pn)
	if pro and pro:GetDisplayName() ~= "" then
		pname= pro:GetDisplayName()
	end
	args[#args+1]= Def.ActorFrame{
		Name= "decs" .. pn, InitCommand= function(self)
			self:xy(mx, my)
		end,
		frame:create_actors(
			"frame", 2, sect_width, sect_height, pcolor, solar_colors.bg(),
			sect_width/2, sect_height/2),
		normal_text("name", pname, pcolor, 8, line_height / 2, 1, left),
		bpm:create_actors("bpm", pn, sect_width/2, line_height*1.5),
	}
	args[#args+1]= menu:create_actors(
		"m" .. pn, mx, my+line_height*2.5, sect_width, sect_height,
		option_set_elements, pn)
	menus[pn]= menu
	bpm_disps[pn]= bpm
	frames[pn]= frame
end

local mine_effect_eles= {}
for i, name in ipairs(sorted_mine_effect_names) do
	mine_effect_eles[#mine_effect_eles+1]=
		generic_mine_effect_element(name)
end

local boost_mods= {
	"Boost", "Brake", "Wave", "Expand", "Boomerang",
}

local hidden_mods= {
	"Hidden", "HiddenOffset", "Sudden", "SuddenOffset",
}

local perspective_mods= {
	"Incoming", "Space", "Hallway", "Distant", "Skew", "Tilt"
}

local sickness_mods= {
	 "Beat", "Bumpy","Drunk", "Tipsy", "Tornado",
}

local size_mods= {
	"Mini", "Tiny",
}

local spin_mods= {
	"Confusion", "Dizzy", "Roll", "Twirl",
}

local target_mods= {
	"Reverse", "Alternate", "Centered", "Cross", "Flip", "Invert", "Split",
	"Xmode", "Blind", "Dark",
}

local visibility_mods= {
	"Blink", "RandomVanish", "Stealth",
	-- "PlayerAutoPlay", "Cover", "Passmark", TODO?  Add support for these mods.
}

local floaty_mods= {
	{ name= "Boost", meta= options_sets.menu,
		args= make_menu_of_float_set(boost_mods) },
	{ name= "Hidden", meta= options_sets.menu,
		args= make_menu_of_float_set(hidden_mods) },
	{ name= "Sickness", meta= options_sets.menu,
		args= make_menu_of_float_set(sickness_mods) },
	{ name= "Size", meta= options_sets.menu,
		args= make_menu_of_float_set(size_mods) },
	{ name= "Spin", meta= options_sets.menu,
		args= make_menu_of_float_set(spin_mods, true) },
	{ name= "Target", meta= options_sets.menu,
		args= make_menu_of_float_set(target_mods) },
	{ name= "Visibility", meta= options_sets.menu,
		args= make_menu_of_float_set(visibility_mods) },
	{ name= "Side Swap", meta= options_sets.adjustable_float,
		args= extra_for_sideswap() },
}

local chart_mods= {
	ass_bools("Turn", {"Mirror", "Backwards", "Left", "Right",
										 "Shuffle", "SoftShuffle", "SuperShuffle"}),
	ass_bools("Inserts", {"Big", "BMRize", "Echo", "Floored", "Little",
												"Planted", "AttackMines", "Quick", "Skippy", "Stomp",
												"Twister", "Wide"}),
	ass_bools("No", {"HoldRolls", "NoJumps","NoHands","NoQuads", "NoStretch",
									 "NoLifts", "NoFakes", "NoMines"}),
}

local song_options= {
	--song_enum("Autosync", AutosyncType, "AutosyncSetting"),
	--song_enum("Sound Effect", SoundEffectType, "SoundEffectSetting"),
}

local special= {
	{ name= "Distortion", meta= options_sets.special_functions,
		args= {
			eles= {
				{ name= "On", init= function() return global_distortion_mode end,
					set= function() global_distortion_mode= true end,
					unset= function() global_distortion_mode= false end}}}},
	{ name= "Color palette", meta= options_sets.special_functions,
		args= {
			eles= {
				{ name= "Light", init= noop_false,
					set= solar_colors.set_light_map,
					unset= noop_nil},
				{ name= "Dark", init= noop_false,
					set= solar_colors.set_dark_map,
					unset= noop_nil}}}},
	{ name= "Judgement", meta= options_sets.mutually_exclusive_special_functions,
		args= {eles= {
						 generic_fake_judge_element("Random"),
						 generic_fake_judge_element("TapNoteScore_Miss"),
						 generic_fake_judge_element("TapNoteScore_W5"),
						 generic_fake_judge_element("TapNoteScore_W4"),
						 generic_fake_judge_element("TapNoteScore_W3"),
						 generic_fake_judge_element("TapNoteScore_W2"),
						 generic_fake_judge_element("TapNoteScore_W1"),
			 }}},
	{ name= "Mine Effects",
		meta= options_sets.mutually_exclusive_special_functions,
		args= { eles= mine_effect_eles }},
	song_bools("Assist", {"AssistClap", "AssistMetronome", "SaveScore", }),
--	{ name= "Song Options", meta= options_sets.menu, args= song_options},
	{ name= "Driven Min", meta= options_sets.adjustable_float,
		args= extra_for_dspeed_min("Driven Min")},
	{ name= "Driven Max", meta= options_sets.adjustable_float,
		args= extra_for_dspeed_max("Driven Max")},
	-- TODO?  Add support for these?
	--"StaticBackground", "RandomBGOnly", "SaveReplay" }),
}

local eval_flag_eles= {}
for i, fname in ipairs(sorted_eval_flag_names) do
	eval_flag_eles[i]= generic_flag_control_element("eval", fname)
end
local gameplay_flag_eles= {}
for i, fname in ipairs(sorted_gameplay_flag_names) do
	gameplay_flag_eles[i]= generic_flag_control_element("gameplay", fname)
end
local interface_flag_eles= {}
for i, fname in ipairs(sorted_interface_flag_names) do
	interface_flag_eles[i]= generic_flag_control_element("interface", fname)
end

local playback_options= {
	{ name= "Rate", meta= options_sets.rate_mod,
		args= { default_value= 1, incs= {.1, .01, -.01, -.1}}},
	{ name= "Haste", meta= options_sets.adjustable_float,
		args= extra_for_haste()},
}

local decorations= {
	{ name= "Evaluation Flags", meta= options_sets.special_functions,
		args= { eles= eval_flag_eles}},
	{ name= "Gameplay Flags", meta= options_sets.special_functions,
		args= { eles= gameplay_flag_eles}},
	{ name= "Interface Flags", meta= options_sets.special_functions,
		args= { eles= interface_flag_eles}},
	{ name= "Sigil Detail", meta= options_sets.adjustable_float,
		args= extra_for_sigil_detail()},
	{ name= "Sigil Size", meta= options_sets.adjustable_float,
		args= extra_for_sigil_size()},
	{ name= "Noteskin", meta= options_sets.noteskins},
}

local profile_options= {
	{ name= "Weight", meta= options_sets.adjustable_float,
	  args= make_profile_float_extra("WeightPounds")},
	{ name= "Voomax", meta= options_sets.adjustable_float,
	  args= make_profile_float_extra("Voomax")},
	{ name= "Birth Year", meta= options_sets.adjustable_float,
	  args= make_profile_float_extra("BirthYear")},
	{ name= "Calorie Method", meta= options_sets.boolean_option,
		args= make_profile_bool_extra(
			"Calorie Method","Heart Rate","Step Count","IgnoreStepCountCalories")},
	{ name= "Gender", meta= options_sets.boolean_option,
		args= make_profile_bool_extra("Gender", "Male", "Female", "IsMale")},
}

local life_options= {
	player_enum("Life", LifeType, "LifeSetting"),
	player_enum("Drain", DrainType, "DrainSetting"),
	player_enum("Fail", FailType, "FailSetting"),
	{ name= "Battery Lives", meta= options_sets.adjustable_float,
		args= extra_for_lives()},
}

local base_options= {
	{ name= "Speed", meta= options_sets.speed},
	{ name= "Playback Options", meta= options_sets.menu, args= playback_options},
	{ name= "Steps", meta= options_sets.steps_list},
	{ name= "Perspective", meta= options_sets.menu,
		args= make_menu_of_float_set(perspective_mods) },
	{ name= "Decorations", meta= options_sets.menu, args= decorations},
	{ name= "Special", meta= options_sets.menu, args= special},
	{ name= "Profile Options", meta= options_sets.menu, args= profile_options},
	{ name= "Life Options", meta= options_sets.menu, args= life_options},
	{ name= "Song tags", meta= options_sets.tags_menu, args= true},
	{ name= "Chart mods", meta= options_sets.menu, args= chart_mods},
	{ name= "Floaty mods", meta= options_sets.menu, args= floaty_mods},
	--{ name= "Clear", meta= options_sets.special_functions,
	--	args= { eles= {{name= "clearall", init= noop_false,
	--									set= set_clear_for_player, unset= noop_false}}}},
}

function args:InitCommand()
	for pn, menu in pairs(menus) do
		menu:push_options_set_stack(options_sets.menu, base_options)
		menu:update_cursor_pos()
	end
end

function args:ExitOptionsCommand()
	SCREENMAN:SetNewScreen("ScreenStageInformation")
end

local function input(event)
	if event.type == "InputEventType_Release" then return end
	local pn= event.PlayerNumber
	local code= event.GameButton
	if menus[pn] then
		if not menus[pn]:interpret_code(code) then
			if code == "Start" then
				local all_on_exit= true
				for k, m in pairs(menus) do
					if not m:can_exit_screen() then
						all_on_exit= false
					end
				end
				if all_on_exit then
					SCREENMAN:GetTopScreen():queuecommand("ExitOptions")
				end
			end
		end
	end
end

args[#args+1]= Def.Actor{
	Name= "code_interpreter",
	OnCommand= function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(input)
	end,
}

return Def.ActorFrame(args)
