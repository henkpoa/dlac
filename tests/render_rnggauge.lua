-- Record actual gauge geometry for the offline preview. No alternate UI.
table.insert(package.loaders or package.searchers, 1, function(name)
    local rel=name:match('^dlac\\(.+)$');
    if rel then return loadfile((rel:gsub('\\','/'))..'.lua'); end
end);
local out=assert(io.open('rng-gauge-draw.txt','w'));
local dl={};
for _,name in ipairs({'AddLine','AddTriangleFilled','AddRectFilled','AddText'}) do
    dl[name]=function(_, ...)
        local parts={name};
        for _,arg in ipairs({...}) do
            if type(arg)=='table' then parts[#parts+1]=table.concat(arg,','); else parts[#parts+1]=tostring(arg); end
        end
        out:write(table.concat(parts,'|'),'\n');
    end;
end
local draw=require('dlac\\servers\\ascensionxi\\modules\\rnggauge\\draw');
for i,v in ipairs({
    {phase=1,progress=0,remaining=0,now=1,flash=0},
    {phase=2,progress=0.42,remaining=1.4,now=1,flash=0},
    {phase=0,progress=1,remaining=0,now=1,flash=0.7},
}) do
    draw.panel(dl,function(c) return c; end,20,25+(i-1)*145,2,v,function(s) return #s*8,16; end);
end
out:close();
