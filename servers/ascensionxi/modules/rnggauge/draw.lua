-- Ranger's arrow: green enamel, aged brass, a recurve bow at the grip.
-- Pure draw-list geometry keeps the gauge sharp at every UI scale.
local M = { W = 264, H = 56 };
function M.size(s) return M.W * (s or 1), M.H * (s or 1); end
function M.panel(dl, u32, x, y, s, v, measure)
    local p = math.max(0, math.min(1, v.progress or 0));
    local aiming, full = v.phase == 1, v.phase == 0;
    local alpha = full and 0.78 or 1;
    local function color(r,g,b,a) return u32({r,g,b,(a or 1)*alpha}); end
    local function pos(a,b) return { x+a*s, y+b*s }; end
    local function line(a,b,c,d,col,w) dl:AddLine(pos(a,b),pos(c,d),col,(w or 1)*s); end
    local function rect(a,b,c,d,col,r) dl:AddRectFilled(pos(a,b),pos(c,d),col,(r or 0)*s); end
    local function tri(a,b,c,d,e,f,col) dl:AddTriangleFilled(pos(a,b),pos(c,d),pos(e,f),col); end
    local brass = color(0.70,0.57,0.31);
    local edge = color(0.91,0.80,0.50);
    local ink = color(0.025,0.05,0.04,0.91);
    local green = aiming and color(0.67,0.55,0.29) or color(0.29,0.73,0.51);
    local light = color(0.69,0.94,0.69);
    -- The compact, quiet backplate keeps the bar legible against bright zones.
    rect(2,5,260,51,ink,9);
    line(43,11,241,11,color(0.70,0.57,0.31,0.25));
    line(43,45,241,45,color(0.70,0.57,0.31,0.25));
    -- Recurve bow, string and nocked arrow.
    local bow = { {24,9},{18,12},{22,17},{29,22},{31,28},{29,34},{22,39},{18,44},{24,47} };
    for i=1,#bow-1 do
        line(bow[i][1],bow[i][2],bow[i+1][1],bow[i+1][2],brass,3);
    end
    local tension = aiming and 5 + math.sin(v.now * 3) * 0.5 or 5 * (1-p);
    line(24,9,18-tension,28,color(0.86,0.85,0.68,0.8));
    line(18-tension,28,24,47,color(0.86,0.85,0.68,0.8));
    line(9,28,42,28,full and light or edge,1.5);
    tri(44,28,37,25,37,31,full and light or edge);
    line(11,28,7,24,brass); line(11,28,7,32,brass);
    rect(28,24,32,32,color(0.22,0.17,0.10),1);
    -- Arrow-shaped recovery track. Fill expands toward the fixed arrowhead.
    rect(52,23,237,35,color(0.14,0.22,0.18),2);
    tri(247,29,235,20,235,38,color(0.14,0.22,0.18));
    line(52,21,235,21,brass); line(52,37,235,37,brass);
    line(235,21,247,29,brass); line(247,29,235,37,brass);
    if p > 0 then
        local endX = 52 + 183*p;
        rect(52,24,endX,34,green,1);
        rect(52,24,endX,26,color(0.70,0.94,0.70,0.44),1);
        if full then tri(244,29,235,23,235,35,green);
        else line(endX,23,endX,35,light,1.5); end
    end
    -- Fletching identifies this as a ranged gauge even without a text label.
    for i=0,2 do
        local a=49-i*4;
        line(a,24,a-3,20,brass); line(a,34,a-3,38,brass);
    end
    if aiming then
        local a=0.35+0.25*(1+math.sin(v.now*4))/2;
        local sweep=53+(v.now%1.6)/1.6*160;
        rect(sweep,25,sweep+20,33,color(0.74,0.60,0.31,a),1);
    elseif v.remaining > 0 then
        local text=string.format('%.1f', math.ceil(v.remaining*10)/10);
        local tw,th=measure(text);
        dl:AddText({x+(148*s)-tw/2,y+(29*s)-th/2},color(0.91,0.96,0.87),text);
    end
    if (v.flash or 0)>0 then
        line(52,20,235,20,color(0.80,1,0.70,v.flash),2);
        line(52,38,235,38,color(0.80,1,0.70,v.flash),2);
    end
end
function M.tooltip(v)
    if v.phase == 1 then return 'Drawing your ranged weapon.\nThe bar fills during recovery after the shot.'; end
    if v.phase == 2 then return string.format('Ranged attack recovery: %.1f seconds\nMelee attacks also delay your next shot.',v.remaining); end
    return 'Ranged attack cooldown complete.\nDrag to move. /dl gauge lock to lock in place.';
end
return M;
