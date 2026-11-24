-- Original numeric teaching engine; no CAS calls or trial dependencies.
function fmt(x)
 if x~=x or math.abs(x)==math.huge then error('Result is outside numeric range.') end
 if math.abs(x)<1e-12 then x=0 end
 return string.format('%.10g',x)
end
function need(ok,msg) if not ok then error(msg,0) end end
function integer(n) return n==math.floor(n) and n>=1 and n<=10000 end
TOOLS={
 {'Linear equation','a,b,c for a*x+b=c','2,3,11',function(v)
 local a,b,c=unpack(v); if a==0 then return {'0*x='..fmt(c-b),b==c and 'All real x solve this.' or 'No solution.'} end
 return {'Subtract b: a*x='..fmt(c-b),'Divide by a: x='..fmt((c-b)/a)} end,3},
 {'Quadratic roots','a,b,c for a*x^2+b*x+c=0','1,-5,6',function(v)
 local a,b,c=unpack(v); need(a~=0,'a must be nonzero. Use Linear equation.')
 local d=b*b-4*a*c; local h=-b/(2*a); local k=a*h*h+b*h+c
 local r={'D=b^2-4ac='..fmt(d),'Vertex h=-b/(2a)='..fmt(h),'Vertex k=f(h)='..fmt(k),'x=(-b +/- sqrt(D))/(2a)'}
 if d<0 then r[#r+1]='x='..fmt(h)..' +/- '..fmt(math.sqrt(-d)/math.abs(2*a))..' i'
 elseif d==0 then r[#r+1]='Repeated root: '..fmt(h)
 else local q=-0.5*(b+(b>=0 and 1 or -1)*math.sqrt(d)); r[#r+1]='Roots: '..fmt(q/a)..', '..fmt(c/q) end
 return r end,3},
 {'Line through points','x1,y1,x2,y2','1,2,3,8',function(v)
 local x,y,u,w=unpack(v); need(x~=u or y~=w,'Two distinct points are required.')
 if x==u then return {'Same x: vertical line.','Equation x='..fmt(x),'Slope is undefined.'} end
 local m=(w-y)/(u-x); return {'m=(y2-y1)/(x2-x1)='..fmt(m),'b=y1-m*x1='..fmt(y-m*x),'y=('..fmt(m)..')x+('..fmt(y-m*x)..')'} end,4},
 {'Two-equation system','a,b,c,d,e,f: ax+by=c; dx+ey=f','1,1,5,2,-1,1',function(v)
 local a,b,c,d,e,f=unpack(v); local det=a*e-b*d
 if det==0 then
 if (a==0 and b==0 and c~=0) or (d==0 and e==0 and f~=0) or a*f~=c*d or b*f~=c*e then return {'Determinant=0.','Inconsistent: no solution.'} end
 return {'Determinant=0.','Dependent: infinitely many solutions.'} end
 return {'D=ae-bd='..fmt(det),'x=(ce-bf)/D='..fmt((c*e-b*f)/det),'y=(af-cd)/D='..fmt((a*f-c*d)/det)} end,6},
 {'Exponential equation','a,b,c for a*b^x=c','3,2,21',function(v)
 local a,b,c=unpack(v); need(a~=0 and b>0 and b~=1 and c/a>0,'Need a!=0, b>0, b!=1, c/a>0.')
 return {'Isolate b^x=c/a='..fmt(c/a),'x=ln(c/a)/ln(b)','x='..fmt(math.log(c/a)/math.log(b))} end,3},
 {'Logarithm','base,value for log_base(value)','2,32',function(v)
 local b,x=unpack(v); need(b>0 and b~=1 and x>0,'Need base>0, base!=1, value>0.')
 return {'Change base: ln(value)/ln(base).','Answer='..fmt(math.log(x)/math.log(b))} end,2},
 {'Compound growth','P,r,t (r decimal per period)','100,0.05,3',function(v)
 local p,r,t=unpack(v); need(p>=0 and r> -1 and t>=0,'Need P>=0, r>-1, t>=0.')
 return {'Growth factor 1+r='..fmt(1+r),'A=P*(1+r)^t','A='..fmt(p*(1+r)^t),'Change A-P='..fmt(p*((1+r)^t-1))} end,3},
 {'Degree trig values','angle in degrees','30',function(v)
 local x=(v[1]%360)*math.pi/180; local s,c=math.sin(x),math.cos(x)
 return {'Radians=degrees*pi/180','sin='..fmt(s),'cos='..fmt(c),math.abs(c)<1e-12 and 'tan undefined at this angle.' or 'tan='..fmt(s/c)} end,1},
 {'Sine equation','s for sin(x)=s; degrees in [0,360)','0.5',function(v)
 local s=v[1]; need(math.abs(s)<=1,'Sine must be in [-1,1].')
 local a=math.asin(s)*180/math.pi; local x=a%360; local y=(180-a)%360
 return {'Principal asin(s)='..fmt(a)..' degrees','First angle='..fmt(x),x==y and 'Only one distinct angle.' or 'Second angle='..fmt(y),'General solutions: add 360*k.','k is any integer.'} end,1},
 {'Cosine law (SAS)','side a,side b,included C degrees','5,7,60',function(v)
 local a,b,c=unpack(v); need(a>0 and b>0 and c>0 and c<180,'Sides>0; included angle between 0 and 180.')
 local z=a*a+b*b-2*a*b*math.cos(c*math.pi/180)
 return {'c^2=a^2+b^2-2ab*cos(C)','c^2='..fmt(z),'c='..fmt(math.sqrt(z)),'Area=ab*sin(C)/2='..fmt(a*b*math.sin(c*math.pi/180)/2)} end,3},
 {'Arithmetic sequence','first term,difference,n','4,3,10',function(v)
 local a,d,n=unpack(v); need(integer(n),'n must be an integer from 1 to 10000.')
 local z=a+(n-1)*d; return {'a_n=a1+(n-1)*d='..fmt(z),'S_n=n*(a1+a_n)/2','S_n='..fmt(n*(a+z)/2)} end,3},
 {'Geometric sequence','first term,ratio,n','8,0.5,4',function(v)
 local a,r,n=unpack(v); need(integer(n),'n must be an integer from 1 to 10000.')
 local sum=0; local t=a; for i=1,n do sum=sum+t; if i<n then t=t*r end end
 return {'a_n=a1*r^(n-1)='..fmt(t),'Sum of first n terms='..fmt(sum),math.abs(r)<1 and 'Infinite sum=a1/(1-r)='..fmt(a/(1-r)) or 'Infinite geometric formula needs |r|<1.'} end,3},
 {'Combinations','n,r for n choose r','6,2',function(v)
 local n,r=unpack(v); need(n>=0 and n<=170 and n==math.floor(n) and r>=0 and r<=n and r==math.floor(r),'Integers: 0<=r<=n<=170.')
 local k=math.min(r,n-r); local z=1; for i=1,k do z=z*(n-k+i)/i end
 return {'nCr=n!/(r!*(n-r)!)','Cancel factorial factors before multiplying.','nCr='..fmt(z),'Order does not matter.'} end,2},
 {'Vector operations','ux,uy,vx,vy','3,4,1,0',function(v)
 local a,b,c,d=unpack(v); local u=math.sqrt(a*a+b*b); local w=math.sqrt(c*c+d*d); local dot=a*c+b*d
 local r={'|u|='..fmt(u)..'; |v|='..fmt(w),'u dot v='..fmt(dot)}
 if u>0 and w>0 then r[#r+1]='angle=acos(dot/(|u||v|))'; r[#r+1]=fmt(math.acos(math.max(-1,math.min(1,dot/u/w)))*180/math.pi)..' degrees' else r[#r+1]='Angle undefined for zero vector.' end return r end,4},
 {'Complex multiplication','a,b,c,d for (a+bi)*(c+di)','2,3,1,-4',function(v)
 local a,b,c,d=unpack(v); return {'Real part ac-bd='..fmt(a*c-b*d),'Imaginary part ad+bc='..fmt(a*d+b*c),'Answer ('..fmt(a*c-b*d)..') + ('..fmt(a*d+b*c)..')i'} end,4},
 {'Synthetic division','r,a,b,c,d: cubic / (x-r)','1,1,-6,11,-6',function(v)
 local r,a,b,c,d=unpack(v); local q=b+r*a; local z=c+r*q; local rem=d+r*z
 return {'Bring down a='..fmt(a),'Next b+r*a='..fmt(q),'Next c+r*previous='..fmt(z),'Remainder d+r*previous='..fmt(rem),'Quotient: ('..fmt(a)..')x^2+('..fmt(q)..')x+('..fmt(z)..')',rem==0 and 'x-r is a factor.' or 'x-r is not a factor.'} end,5}
}
function solve(index,input)
 local tool=TOOLS[index]; local values={}
 if input:match('^%s*,') or input:match(',%s*$') or input:match(',%s*,') then return {'Input error: empty field.'} end
 for s in input:gmatch('[^,]+') do
 local n=tonumber(s); if not n or n~=n or math.abs(n)>1e100 then return {'Input error: use finite decimal numbers.','Separate numbers with commas; no expressions.'} end
 values[#values+1]=n end
 if #values~=tool[5] then return {'Input error: expected '..tool[5]..' numbers.',tool[2]} end
 local ok,res=pcall(tool[4],values); if not ok then return {'Cannot solve:',tostring(res)} end
 return res
end
