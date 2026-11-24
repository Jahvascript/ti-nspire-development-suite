-- TNS Studio original note reader. MIT license.
local top,lines,cacheWidth=1,{},-1
local rowHeight=17
local sizes={9,10,11,12,24}
local function charend(s,i)
 local b=s:byte(i) or 0
 return math.min(#s,i+(b>=240 and 3 or b>=224 and 2 or b>=192 and 1 or 0))
end
local function wrap(gc,s,width)
 local result={}
 for paragraph in (s.."\n"):gmatch("(.-)\n") do
  local current=""
  for word in paragraph:gmatch("%S+") do
   local candidate=current=="" and word or current.." "..word
   if gc:getStringWidth(candidate)<=width then current=candidate
   else
    if current~="" then result[#result+1]=current;current="" end
    local i=1
    while i<=#word do
     local j=charend(word,i);local ch=word:sub(i,j)
     if current~="" and gc:getStringWidth(current..ch)>width then result[#result+1]=current;current="" end
     current=current..ch;i=j+1
    end
   end
  end
  result[#result+1]=current
 end
 return result
end
local function capacity() return math.max(1,math.floor((platform.window:height()-60)/rowHeight)) end
local function move(n) top=math.max(1,math.min(math.max(1,#lines-capacity()+1),top+n));platform.window:invalidate() end
function on.paint(gc)
 local w,h=platform.window:width(),platform.window:height()
 gc:setColorRGB(247,249,252);gc:fillRect(0,0,w,h)
 gc:setColorRGB(21,49,68);gc:fillRect(0,0,w,30)
 gc:setFont("sansserif","b",11);gc:setColorRGB(255,255,255)
 gc:clipRect("set",8,0,w-16,30);gc:drawString(TITLE,8,7,"top");gc:clipRect("reset")
 gc:setFont("sansserif","r",FONT)
 rowHeight=gc:getStringHeight("Ag")+3
 if cacheWidth~=w then lines=wrap(gc,BODY,w-20);cacheWidth=w end
 top=math.max(1,math.min(math.max(1,#lines-capacity()+1),top))
 gc:setColorRGB(26,40,50)
 for i=0,capacity()-1 do if lines[top+i] then gc:drawString(lines[top+i],10,37+i*rowHeight,"top") end end
 gc:setColorRGB(21,49,68);gc:fillRect(0,h-22,w,22)
 gc:setFont("sansserif","r",9);gc:setColorRGB(255,255,255)
 gc:drawString("Up/Down scroll  |  "..top.."/"..math.max(1,#lines),8,h-18,"top")
end
function on.arrowKey(k) if k=="up" then move(-1) elseif k=="down" then move(1) elseif k=="left" then move(-capacity()) elseif k=="right" then move(capacity()) end end
function on.charIn(c)
 local index=1;for i,v in ipairs(sizes) do if v==FONT then index=i end end
 if c=="+" then index=math.min(#sizes,index+1) elseif c=="-" then index=math.max(1,index-1) else return end
 FONT=sizes[index];cacheWidth=-1;platform.window:invalidate()
end
function on.resize() cacheWidth=-1;platform.window:invalidate() end
