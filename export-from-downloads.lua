local function sanitize(name)
	return (name:gsub('[<>:"/\\|%?%*]', "_"))
end

local function ensureDir(path)
	os.execute(('powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path \\"%s\\" | Out-Null"'):format(path))
end

local function writeFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text or "")
	f:close()
end

local function getSource(inst)
	-- Remodel-safe way (works when inst.Source is not available)
	if remodel.getRawProperty then
		local ok, src = pcall(remodel.getRawProperty, inst, "Source")
		if ok then return src end
	end

	-- Fallback (some builds do support it)
	local ok, src = pcall(function() return inst.Source end)
	if ok then return src end

	return nil
end

local function exportScriptsUnder(rootInstance, outDir)
	if not rootInstance then return end

	local function isLuauContainer(inst)
		local c = inst.ClassName
		return c == "Script" or c == "LocalScript" or c == "ModuleScript"
	end

	local function extFor(inst)
		if inst.ClassName == "Script" then return ".server.lua" end
		if inst.ClassName == "LocalScript" then return ".client.lua" end
		return ".lua"
	end

	local function relFolderFor(inst)
		local parts = {}
		local cur = inst.Parent
		while cur and cur ~= rootInstance do
			table.insert(parts, 1, sanitize(cur.Name))
			cur = cur.Parent
		end
		if #parts == 0 then return outDir end
		return outDir .. "/" .. table.concat(parts, "/")
	end

	local function visit(node)
		if isLuauContainer(node) then
			local src = getSource(node)
			if src ~= nil then
				local folder = relFolderFor(node)
				ensureDir(folder)
				local filePath = folder .. "/" .. sanitize(node.Name) .. extFor(node)
				writeFile(filePath, src)
			else
				-- If this happens, the model file didn’t include script source for that script
				-- (rare for your own scripts, but possible)
				print(("Skipping %s (%s): no Source available"):format(node.Name, node.ClassName))
			end
		end

		for _, child in ipairs(node:GetChildren()) do
			visit(child)
		end
	end

	visit(rootInstance)
end

local function exportModelFile(path, outDir)
	local roots = remodel.readModelFile(path) -- returns array
	for _, root in ipairs(roots) do
		exportScriptsUnder(root, outDir)
	end
end

local outRoot = "src"

-- Your downloads:
exportModelFile("Modules.rbxmx", outRoot .. "/ServerScriptService/Modules")
exportModelFile("StarterPlayerScripts.rbxmx", outRoot .. "/StarterPlayer/StarterPlayerScripts")

print("Done exporting downloads into /src")