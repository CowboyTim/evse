require "bit32"
require "string"

local args = { ... }
if #args == 0 then
    print("Need 1 argument: XOR key")
    return
end

local tbl_xor_key = args[1]
local function xorf(data)
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
	  s = string.format("%c", bit32.bxor(str:byte(i), v))
	  table.insert(d, s)
	end

	return table.concat(d, "")
end

local function to_hex(data)
    local char, sh, i
	local d = {}
    for i = 1, #data do
        char = string.sub(data, i, i)
        sh = string.format("%02x", string.byte(char))
        table.insert(d, sh)
    end
	return table.concat(d, "")
end



local bcencrypt = Proto("bcencrypt", "Websocket OCPP1.6J bcencrypt")
local f_command = ProtoField.string("bcencrypt.command", "Websocket JSON command/response")
local f_data_a  = ProtoField.string("bcencrypt.data", "Websocket data in ASCII")
local f_data_h  = ProtoField.string("bcencrypt.hex", "Websocket data in HEX")
bcencrypt.fields.command     = f_command
bcencrypt.fields.data        = f_data_a
bcencrypt.fields.hex         = f_data_h
local function do_ws_bcencrypt(tvb, pinfo, root)
	--print("START")
    if tvb:len() == 0 then 
		--print("EMPTY")
		return
    end
	pinfo.cols.protocol = bcencrypt.name
    --orig:call(tvb, pinfo, root)
    local subtree = root:add(bcencrypt, tvb(0))
    subtree:add(f_data_a, tvb())
    subtree:add(f_data_h, to_hex(tvb:raw()))

	local k,l = pcall(xorf, tvb)
    if k == false then
	    print(k,l)
    end
    --print(xorf(tvb))
	local da = xorf(tvb())
	--print("STR:"..da)
  	subtree:add(f_command, da)
	
	--print("END")
    return
end
function bcencrypt.dissector(tvb, pinfo, root)
    local k, l = pcall(do_ws_bcencrypt,tvb, pinfo, root)
    if k == false then
	    print(k,l)
    end
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
