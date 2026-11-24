platform.apiLevel='2.0'
S={screen='home',selected=1,scroll=0,query='',input='',lesson=1,tool=1,answer=false,done={},score={}}
function redraw() platform.window:invalidate() end
function go(screen) S.screen=screen; S.selected=1; S.scroll=0; S.query=''; redraw() end
function items()
 local a={}
 if S.screen=='home' then return {{'Lessons & worked examples',1},{'Step-by-step calculators',2},{'Practice & progress',3},{'Help & calculator setup',4}} end
 local src=S.screen=='tools' and TOOLS or LESSONS
 for i,v in ipairs(src) do
 local name=S.screen=='tools' and v[1] or v[1]..': '..v[2]
 if name:lower():find(S.query:lower(),1,true) then a[#a+1]={name,i} end end
 return a
end
function ismenu() return S.screen=='home' or S.screen=='lessons' or S.screen=='tools' or S.screen=='practice' end
function lines()
 if S.screen=='lesson' then local l=LESSONS[S.lesson]; local a={l[3],'','WORKED EXAMPLE'}; for x in l[4]:gmatch('[^|]+') do a[#a+1]=x end; a[#a+1]=''; a[#a+1]='M: mark studied / unmark'; a[#a+1]='Status: '..(S.done[S.lesson] and 'studied' or 'not marked'); return a
 elseif S.screen=='quiz' then local l=LESSONS[S.lesson]; return {l[5],'',S.answer and ('Answer: '..l[6]) or 'Try it on paper. Enter reveals answer.',S.answer and 'Y: got it right   N: review again' or '',S.score[S.lesson] and ('Last result: '..S.score[S.lesson]) or ''}
 elseif S.screen=='result' then return S.result
 elseif S.screen=='input' then return {TOOLS[S.tool][2],'','Numbers separated by commas.','Decimals or scientific notation; no formulas.','All angle tools use DEGREES.','','Input: '..S.input,'','Enter: calculate   Del: erase','Tab: fill example'}
 else return {'PRECALCULUS STUDIO 1.0','Original lessons and numeric teaching tools.','36 lessons; 16 calculators; 36 practice prompts.','','Arrows: select / scroll. Enter: open.','Esc: back. In lists, type to filter.','Del: remove last typed character.','Lessons: M marks studied.','Practice: Enter reveals; Y/N self-assess.','Save this TNS document to retain progress.','','Tools use decimal numbers, not expressions.','Angle tools always use degrees, independent of document settings.','Answers are rounded to 10 significant digits.','This is a tutorial, not a general symbolic solver.','','Non-CAS check: add a Calculator or Graphs page to verify your work.','Graph a function, then use Analyze Graph to locate zeros or intersections.','Confirm document angle mode for trig checks.','','All features included; no activation or trial locks.'} end
end
function title()
 if S.screen=='lesson' or S.screen=='quiz' then return LESSONS[S.lesson][2] end
 if S.screen=='input' or S.screen=='result' then return TOOLS[S.tool][1] end
 return ({home='Precalculus Studio',lessons='Learn',tools='Calculate',practice='Practice',help='Help'})[S.screen] or 'Studio'
end
function wrap(gc,text,width)
 local out={}; local line=''
 for word in tostring(text):gmatch('%S+') do
 if gc:getStringWidth(line..(line=='' and '' or ' ')..word)>width and line~='' then out[#out+1]=line;line='' end
 while gc:getStringWidth(word)>width do local k=#word; while k>1 and gc:getStringWidth(word:sub(1,k))>width do k=k-1 end; if line~='' then out[#out+1]=line;line='' end;out[#out+1]=word:sub(1,k);word=word:sub(k+1) end
 line=line..(line=='' and '' or ' ')..word end
 out[#out+1]=line;return out
end
function on.paint(gc)
 local w,h=platform.window:width(),platform.window:height()
 gc:setColorRGB(248,250,252);gc:fillRect(0,0,w,h)
 gc:setColorRGB(23,48,77);gc:fillRect(0,0,w,29);gc:setFont('sansserif','b',11);gc:setColorRGB(255,255,255);gc:drawString(title(),8,5,'top')
 gc:setFont('sansserif','r',10)
 local cap=math.max(1,math.floor((h-66)/17));local y=34
 if ismenu() then
 local a=items();S.selected=math.max(1,math.min(S.selected,#a));local start=math.floor((S.selected-1)/cap)*cap+1
 for i=start,math.min(#a,start+cap-1) do
 if i==S.selected then gc:setColorRGB(214,232,244);gc:fillRect(3,y-1,w-6,17) end
 gc:setColorRGB(23,48,77); local label=a[i][1];while gc:getStringWidth(label)>w-18 do label=label:sub(1,-2) end;gc:drawString(label,8,y,'top');y=y+17 end
 gc:setColorRGB(70,85,100);gc:drawString(#a==0 and 'No matches. Del clears filter.' or (S.query~='' and ('Find: '..S.query) or (S.selected..' / '..#a..'  Enter: open')),8,h-29,'top')
 else
 local all={};for _,x in ipairs(lines()) do for _,z in ipairs(wrap(gc,x,w-16)) do all[#all+1]=z end end
 S.maxscroll=math.max(0,#all-cap);S.scroll=math.max(0,math.min(S.scroll,S.maxscroll))
 for i=S.scroll+1,math.min(#all,S.scroll+cap) do gc:setColorRGB(23,48,77);gc:drawString(all[i],8,y,'top');y=y+17 end
 gc:setColorRGB(70,85,100);gc:drawString('Lines '..(S.scroll+1)..'-'..math.min(#all,S.scroll+cap)..' / '..#all..'  Up/Down',8,h-29,'top')
 end
 gc:setFont('sansserif','r',9);gc:setColorRGB(70,85,100);gc:drawString('Esc: back   |   Learn - work - check',8,h-14,'top')
end
function on.arrowKey(key)
 local d=(key=='down' or key=='right') and 1 or -1
 if ismenu() then S.selected=math.max(1,math.min(#items(),S.selected+d)) else S.scroll=math.max(0,S.scroll+d) end;redraw()
end
function on.enterKey()
 if ismenu() then local a=items();local v=a[S.selected];if not v then return end
 if S.screen=='home' then go(({'lessons','tools','practice','help'})[v[2]])
 elseif S.screen=='tools' then S.tool=v[2];S.input='';go('input')
 else local practice=S.screen=='practice';S.lesson=v[2];S.answer=false;go(practice and 'quiz' or 'lesson') end
 elseif S.screen=='input' then S.result=solve(S.tool,S.input);go('result')
 elseif S.screen=='quiz' then S.answer=true;redraw() end
end
on.returnKey=on.enterKey
function on.escapeKey()
 local dest=({lesson='lessons',quiz='practice',input='tools',result='input'})[S.screen] or 'home';go(dest)
end
function on.charIn(c)
 if S.screen=='input' then if #S.input<160 then S.input=S.input..c;S.scroll=6 end
 elseif ismenu() and S.screen~='home' then if #S.query<35 then S.query=S.query..c;S.selected=1 end
 elseif S.screen=='lesson' and c:lower()=='m' then S.done[S.lesson]=not S.done[S.lesson]
 elseif S.screen=='quiz' and S.answer and (c:lower()=='y' or c:lower()=='n') then S.score[S.lesson]=c:lower()=='y' and 'correct' or 'review';end;redraw()
end
function on.backspaceKey() if S.screen=='input' then S.input=S.input:sub(1,-2) else S.query=S.query:sub(1,-2);S.selected=1 end;redraw() end
function on.tabKey() if S.screen=='input' then S.input=TOOLS[S.tool][3];redraw() end end
function on.save() return {done=S.done,score=S.score} end
function on.restore(t) if type(t)=='table' then S.done=type(t.done)=='table' and t.done or {};S.score=type(t.score)=='table' and t.score or {} end end
function on.resize() redraw() end
