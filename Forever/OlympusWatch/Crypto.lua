-- RSA-2048 / exponent 65537, RSASSA-PKCS1-v1_5 with SHA-256 (RFC 8017).
-- Verification only: private signing material never enters the addon.
OlympusWatchCrypto={}
local C=OlympusWatchCrypto
local B=4096
function C.Hex(s) return (s:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
function C.Unhex(s)
    if type(s)~='string' or #s%2~=0 or s:find('[^0-9a-f]') then return nil end
    return (s:gsub('..',function(h) return string.char(tonumber(h,16)) end))
end
function C.Hash(s) return OlympusWatchHash.sha256(s) end
local function trim(a) while #a>1 and a[#a]==0 do a[#a]=nil end; return a end
local function big(hex)
    local a={}; for i=#hex,1,-3 do a[#a+1]=tonumber(hex:sub(math.max(1,i-2),i),16) end
    return trim(a)
end
local function compare(a,b)
    if #a~=#b then return #a<#b and -1 or 1 end
    for i=#a,1,-1 do if a[i]~=b[i] then return a[i]<b[i] and -1 or 1 end end
    return 0
end
local function subtract(a,b)
    local out,borrow={},0
    for i=1,#a do local n=a[i]-(b[i] or 0)-borrow; borrow=n<0 and 1 or 0; out[i]=n%B end
    return trim(out)
end
local function twice(a,n)
    local r,carry={},0
    for i=1,#a do local v=a[i]*2+carry; r[i]=v%B; carry=math.floor(v/B) end
    if carry>0 then r[#r+1]=carry end
    if compare(r,n)>=0 then r=subtract(r,n) end; return r
end
local function inverse(a)
    local t,newt,r,newr=0,1,B,a
    while newr~=0 do local q=math.floor(r/newr); t,newt=newt,t-q*newt; r,newr=newr,r-q*newr end
    return (-t)%B
end
local function mont(a,b,n,np,yieldWork)
    local count=#n; local t={}; for i=1,2*count+2 do t[i]=0 end
    for i=1,count do
        local carry=0
        for j=1,count do local k=i+j-1; local v=t[k]+(a[i] or 0)*(b[j] or 0)+carry; t[k]=v%B; carry=math.floor(v/B) end
        t[i+count]=carry
        if yieldWork and i%16==0 then yieldWork() end
    end
    for i=1,count do
        local q=(t[i]*np)%B; local carry=0
        for j=1,count do local k=i+j-1; local v=t[k]+q*n[j]+carry; t[k]=v%B; carry=math.floor(v/B) end
        local k=i+count
        while carry>0 do local v=t[k]+carry; t[k]=v%B; carry=math.floor(v/B); k=k+1 end
        if yieldWork and i%16==0 then yieldWork() end
    end
    local r={}; for i=count+1,2*count+2 do r[#r+1]=t[i] end; trim(r)
    if compare(r,n)>=0 then r=subtract(r,n) end; return r
end
local keyCache={}
function C.Verify(message,signature,modulus,yieldWork)
    if type(message)~='string' or #message>4096 or type(signature)~='string' or #signature~=512 or signature:find('[^0-9a-f]') then return false end
    if type(modulus)~='string' or #modulus~=512 or modulus:find('[^0-9a-f]') or tonumber(modulus:sub(1,1),16)<8 then return false end
    local s,n=big(signature),big(modulus)
    if n[1]%2==0 or compare(s,n)>=0 then return false end
    local cached=keyCache[modulus]
    if not cached then
        local r={1}
        for i=1,24*#n do r=twice(r,n); if yieldWork and i%64==0 then yieldWork() end end
        cached={r2=r,np=inverse(n[1])}; keyCache={[modulus]=cached}
    end
    local base=mont(s,cached.r2,n,cached.np,yieldWork)
    local result=base
    for _=1,16 do result=mont(result,result,n,cached.np,yieldWork) end
    result=mont(result,base,n,cached.np,yieldWork)
    result=mont(result,{1},n,cached.np,yieldWork)
    local parts={}; for i=#result,1,-1 do parts[#parts+1]=string.format('%03x',result[i]) end
    local hex=table.concat(parts):gsub('^0+',''); if #hex>512 then return false end
    hex=string.rep('0',512-#hex)..hex
    local digestInfo='3031300d060960864801650304020105000420'..C.Hash(message)
    local expected='0001'..string.rep('ff',256-3-#digestInfo/2)..'00'..digestInfo
    return hex==expected
end
