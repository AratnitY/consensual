local function input(event)
	if event.type == "InputEventType_Release" then return false end
	local button= event.DeviceInput.button
	if button == "DeviceButton_n" then
	end
end

local args= {
	OnCommand= function(self)
		local screen= SCREENMAN:GetTopScreen()
		SCREENMAN:GetTopScreen():AddInputCallback(input)
	end,
}

return Def.ActorFrame(args)
