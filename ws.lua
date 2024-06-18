require "bit32"
local tbl_xor_key = ""
function xorf(data)
	local l = data:len()
	local d = {}
	local str = data:raw()

	local v, x, c, s, i, j
    j = 1
	for i = 1, l do
	  if j > tbl_xor_key:len() then
		j = 1
      end
      v = tbl_xor_key:byte(j)
	  j = j +1
	  --print("L:"..tostring(l)..",I:"..tostring(i)..",J:"..tostring(j)..",V:"..tostring(v))
	  x = bit32.bxor(str:byte(i), v)
	  c = string.format("%02x", x)
	  s = string.format("%c", x)
	  table.insert(d, s)
	end

	return table.concat(d, "")
end

local bcencrypt = Proto("bcencrypt", "Websocket Text")
local f_command = ProtoField.string("bcencrypt.command", "Websocket command")
local f_data    = ProtoField.string("bcencrypt.data", "Websocket data")
bcencrypt.fields.command = f_command
bcencrypt.fields.data    = f_data
function bcencrypt.dissector(tvb, pinfo, root)
	--print("START")
    if tvb:len() == 0 then 
		--print("EMPTY")
		return
    end
	pinfo.cols.protocol = bcencrypt.name
    --orig:call(tvb, pinfo, root)
    local subtree = root:add(bcencrypt, tvb(0))
    subtree:add(f_data, tvb())

	local k,l = pcall(xorf, tvb)
	--print(k,l)
    --print(xorf(tvb))
	local da = xorf(tvb())
	--print("STR:"..da)
  	subtree:add(f_command, da)
	
	--print("END")
end
function bcencrypt.init()
end
local function mydec(tvb, pinfo, tree)
	bcencrypt.dissector(tvb, pinfo, tree)
    return true -- accept all Websockets data (do not call other dissectors)
end
bcencrypt:register_heuristic("ws",mydec)
local ws_dissector_table = DissectorTable.get("ws.port")
local orig = ws_dissector_table:get_dissector(80)
ws_dissector_table:add(80, bcencrypt)
