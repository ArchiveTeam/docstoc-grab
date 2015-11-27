dofile("urlcode.lua")
dofile("table_show.lua")

local url_count = 0
local tries = 0
local item_type = os.getenv('item_type')
local item_value = os.getenv('item_value')

local downloaded = {}
local addedtolist = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  local url = urlpos["url"]["url"]
  local html = urlpos["link_expect_html"]
  
  if ((downloaded[url] ~= true and addedtolist[url] ~= true) and ((string.match(url, "[^0-9]"..item_value.."[0-9][0-9]") and not string.match(url, "[^0-9]"..item_value.."[0-9][0-9][0-9]")) or html == 0)) or string.match(url, "https?://swf%.docstoc%.com") or string.match(url, "https?://viewer%.docstoc%.com") then
    addedtolist[url] = true
    return true
  else
    return false
  end
end


wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true
  
  local function check(urla)
    local url = string.match(urla, "^([^#]+)")
    if ((downloaded[url] ~= true and addedtolist[url] ~= true) and ((string.match(url, "[^0-9]"..item_value.."[0-9][0-9]") and not string.match(url, "[^0-9]"..item_value.."[0-9][0-9][0-9]")) or string.match(url, "^https?://[^/]*cloudfront%.net") or string.match(url, "^https?://[^/]*docstoccdn%.com"))) or string.match(url, "https?://swf%.docstoc%.com") or string.match(url, "https?://viewer%.docstoc%.com") then
      if string.match(url, "&amp;") then
        table.insert(urls, { url=string.gsub(url, "&amp;", "&") })
        addedtolist[url] = true
        addedtolist[string.gsub(url, "&amp;", "&")] = true
      else
        table.insert(urls, { url=url })
        addedtolist[url] = true
      end
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^//") then
      check("http:"..newurl)
    elseif string.match(newurl, "^/") then
      check(string.match(url, "^(https?://[^/]+)")..newurl)
    end
  end

  if string.match(url, "^https?://swf%.docstoc%.com") and string.match(url, "doc_id=") and string.match(url, "mem_id=") and string.match(url, "ref=") then
    local mem_id = string.match(url, "mem_id=([0-9%-]+)")
    local doc_id = string.match(url, "doc_id=([0-9%-]+)")
    local doc_ref = string.match(url, "ref=([^&]+)")

    check("http://embed.docstoc.com/Flash.asmx/StoreReffer?docID="..doc_id.."&url="..doc_ref)
    check("http://docs.docstoc.com/did/"..mem_id.."/"..doc_id..".did?rev=0")
--    check("http://docs.docstoc.com/did/"..mem_id.."/"..doc_id..".did?rev=1")
    check("http://viewerdata.docstoc.com/getDocumentInfo.ashx?doc_id="..doc_id.."&host_url="..url.."&mem_id="..mem_id)
    check("http://docs.docstoc.com/did/"..mem_id.."/"..doc_id..".did")
    check("http://embed.docstoc.com/handlers/downloadfilefromflash.ashx?docid="..doc_id.."&ref_url="..doc_ref)
    check("http://embed.docstoc.com/handlers/downloadfilefromflash.ashx?docid="..doc_id)
  end
  
  if item_type == '100documents' and string.match(url, "https?://[^/]*docstoc%.com") then
    html = read_file(file)
    for newurl in string.gmatch(html, '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">([^<]+)") do
      checknewurl(newurl)
    end
  end

  return urls
end
  

wget.callbacks.httploop_result = function(url, err, http_stat)
  -- NEW for 2014: Slightly more verbose messages because people keep
  -- complaining that it's not moving or not working
  status_code = http_stat["statcode"]
  
  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. ".  \n")
  io.stdout:flush()

  if downloaded[url["url"]] == true and not (string.match(url["url"], "https?://swf%.docstoc%.com") or string.match(url["url"], "https?://viewer%.docstoc%.com")) then
    return wget.actions.EXIT
  end

  if status_code == 301 and string.match(url["url"], "^http://www%.docstoc%.com/docs/"..item_value.."[0-9][0-9]$") then
    return wget.actions.EXIT
  end

  -- try to find and prevent loops
  for part in string.gmatch(url["url"], "([^/]*)") do
    if string.match(url["url"], "/"..part.."/"..part.."/"..part) then
      return wget.actions.EXIT
    end
  end
  for part in string.gmatch(url["url"], "([^/]*/[^/]*)") do
    if string.match(url["url"], "/"..part.."/"..part) then
      return wget.actions.EXIT
    end
  end
  for part in string.gmatch(url["url"], "([^/]*/[^/]*/[^/]*)") do
    if string.match(url["url"], "/"..part.."/"..part) then
      return wget.actions.EXIT
    end
  end

  if (status_code >= 200 and status_code <= 399) then
    if string.match(url.url, "https://") then
      local newurl = string.gsub(url.url, "https://", "http://")
      downloaded[newurl] = true
    else
      downloaded[url.url] = true
    end
  end
  
  if status_code >= 500 or
    (status_code >= 400 and status_code ~= 404 and status_code ~= 403 and status_code ~= 400 and status_code ~= 414) then
    io.stdout:write("Server returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.ABORT
    else
      return wget.actions.CONTINUE
    end
  elseif status_code == 0 then
    io.stdout:write("\nServer returned "..http_stat.statcode.." ("..err.."). Sleeping.\n")
    io.stdout:flush()
    os.execute("sleep 1")
    tries = tries + 1
    if tries >= 5 then
      io.stdout:write("\nI give up...\n")
      io.stdout:flush()
      tries = 0
      return wget.actions.ABORT
    else
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end
