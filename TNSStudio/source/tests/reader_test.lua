on={};TITLE='A long title';BODY=string.rep('First line with pi π and a longwordabcdefghijklmnopqrstuv.\n',80);FONT=11
local width,height=318,212
platform={window={width=function() return width end,height=function() return height end,invalidate=function() end}}
local size=11;local strings={}
local function count(s)
 local n,i=0,1
 while i<=#s do local b=s:byte(i);local bytes=b<128 and 1 or b<224 and 2 or b<240 and 3 or 4
  for j=i+1,i+bytes-1 do assert(s:byte(j) and s:byte(j)>=128 and s:byte(j)<192,'split UTF-8') end
  n=n+1;i=i+bytes
 end
 return n
end
local gc={setColorRGB=function() end,fillRect=function() end,
 setFont=function(self,f,style,s) assert(s==9 or s==10 or s==11 or s==12 or s==24);size=s end,
 getStringWidth=function(self,s) return count(s)*size*.62 end,
 getStringHeight=function() return math.ceil(size*1.33) end,
 clipRect=function(self,op,...) assert(op=='set' or op=='reset') end,
 drawString=function(self,s,x,y,align) count(s);assert(align=='top');strings[#strings+1]=s end}
dofile(arg[1])
on.paint(gc);assert(#strings>3);local first=strings[#strings]
on.arrowKey('down');strings={};on.paint(gc);assert(strings[#strings]~=first)
for i=1,300 do on.arrowKey('down') end
strings={};on.paint(gc);local last=strings[#strings]
on.arrowKey('down');strings={};on.paint(gc);assert(strings[#strings]==last)
for i=1,20 do on.charIn('+');on.paint(gc) end;assert(FONT==24)
for i=1,20 do on.charIn('-');on.paint(gc) end;assert(FONT==9)
width=120;on.resize();on.paint(gc);on.arrowKey('left');on.paint(gc)
print('PASS: supported graphics API, valid UTF-8 wrapping, scrolling bounds, font limits, narrow-screen resize')
