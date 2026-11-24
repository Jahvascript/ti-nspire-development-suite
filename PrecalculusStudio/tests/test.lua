on={};platform={window={invalidate=function() end,width=function() return 318 end,height=function() return 212 end}}
dofile('PrecalculusStudio.lua')
local count=0
local function check(x) count=count+1;assert(x,'check '..count..' failed') end
local function has(i,s,part) return table.concat(solve(i,s),' '):find(part,1,true)~=nil end
check(#LESSONS==36 and #TOOLS==16)
check(has(1,'2,3,11','x=4'));check(has(1,'0,3,3','All real'));check(has(1,'0,3,2','No solution'))
check(has(2,'1,-5,6','Roots: 3, 2'));check(has(2,'1,0,1','+/- 1 i'));check(has(2,'1,2,1','Repeated root: -1'));check(has(2,'0,2,1','nonzero'))
check(has(3,'1,2,3,8','m=(y2-y1)/(x2-x1)=3'));check(has(3,'1,2,1,9','vertical'));check(has(3,'1,2,1,2','distinct'))
check(has(4,'1,1,5,2,-1,1','x=(ce-bf)/D=2'));check(has(4,'1,1,5,2,2,10','infinitely'));check(has(4,'1,1,5,2,2,9','no solution'));check(has(4,'0,0,1,0,0,0','no solution'))
check(has(5,'3,2,24','x=3'));check(has(5,'1,1,3','Cannot solve'))
check(has(6,'2,32','Answer=5'));check(has(6,'2,-1','Cannot solve'))
check(has(7,'100,0.05,3','115.7625'));check(has(7,'100,-1,3','Cannot solve'))
check(has(8,'30','sin=0.5'));check(has(8,'90','undefined'));check(has(8,'-30','sin=-0.5'))
check(has(9,'0.5','Second angle=150'));check(has(9,'1','one distinct'));check(has(9,'2','Cannot solve'))
check(has(10,'3,4,90','c=5'));check(has(10,'3,4,180','Cannot solve'))
check(has(11,'4,3,10','S_n=175'));check(has(11,'4,3,1.5','Cannot solve'))
check(has(12,'8,0.5,4','terms=15'));check(has(12,'8,1,4','terms=32'));check(has(12,'8,0,1','a_n=a1*r^(n-1)=8'))
check(has(13,'6,2','nCr=15'));check(has(13,'0,0','nCr=1'));check(has(13,'3,4','Cannot solve'))
check(has(14,'3,4,1,0','u dot v=3'));check(has(14,'0,0,1,0','undefined'))
check(has(15,'2,3,1,-4','(14) + (-5)i'));check(has(16,'1,1,-6,11,-6','Remainder d+r*previous=0'))
for i,t in ipairs(TOOLS) do
 check(not has(i,t[3],'error'));check(not has(i,t[3],'Cannot solve'))
 check(has(i,'abc','Input error'));check(has(i,'1,,2','Input error'));check(has(i,'1,','Input error'))
end
-- Finite-precision answer residuals over 100 independent random integer quadratics.
math.randomseed(42)
for i=1,100 do
 local p,q=math.random(-100,100),math.random(-100,100)
 local text=table.concat(solve(2,'1,'..(-(p+q))..','..p*q),' ')
 if p~=q then local x,y=text:match('Roots: ([^,]+), ([^ ]+)');x=tonumber(x);y=tonumber(y);check(x and y and math.abs(x+y-p-q)<1e-6 and math.abs(x*y-p*q)<1e-5) else check(text:find('Repeated root',1,true)) end
end
-- All content routes render at handheld dimensions with a conservative mock font.
local gc={setColorRGB=function()end,fillRect=function()end,setFont=function()end,getStringWidth=function(_,s)return #s*6 end,drawString=function(_,s,x,y)check(y>=0 and y<212)end}
for _,mode in ipairs({'home','lessons','practice','tools','help'}) do go(mode);on.paint(gc) end
for i=1,#LESSONS do S.lesson=i;for _,mode in ipairs({'lesson','quiz'}) do go(mode);on.paint(gc);on.arrowKey('down');on.paint(gc);on.enterKey();on.paint(gc) end end
for i,t in ipairs(TOOLS) do S.tool=i;go('input');on.tabKey();check(S.input==t[3]);on.paint(gc);on.enterKey();check(S.screen=='result');on.paint(gc);on.escapeKey();check(S.screen=='input') end
S.lesson=1;go('lesson');on.charIn('m');check(S.done[1]);go('quiz');on.enterKey();on.charIn('y');check(S.score[1]=='correct');local saved=on.save();S.done={};S.score={};on.restore(saved);check(S.done[1] and S.score[1]=='correct')
go('lessons');on.charIn('quadratic');check(#items()==1);on.enterKey();check(S.screen=='lesson' and S.lesson==10)
go('tools');on.charIn('zzzz');on.enterKey();check(S.screen=='tools');on.paint(gc)
print('PASS: '..count..' assertions; Lua 5.1; numeric, error, route, paint, persistence checks.')
