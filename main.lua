--Curve Tests--

local app = renoise.app()
local tool = renoise.tool()
local vb = renoise.ViewBuilder()
local window_obj = nil
local window_content = nil

local gridsize = {x = 48, y = 48}
local curvegrid = {}
local buffer1 = {}
local buffer2 = {}
local points = { {0.1,0.1,1}, {0.9,0.9,1} } --x,y,weight
local selectedpoint = 1
local padreleased = true
local rainbow_mode = false
local use_x_rainbow = false
local idle_processing = false
local samplesize = 2
local draw_mode = false

local sampled_points = {}

local point_x
local point_y

local pascals_triangle = {}

--BINOMIAL COEFFECIENT---------------------------------
local function binom(n,k)

  if k == 0 or k == n then return 1 end
  if k < 0 or k > n then return 0 end

  if not pascals_triangle[n] then pascals_triangle[n] = {} end
  
  if not pascals_triangle[n][k] then
  
    pascals_triangle[n][k] = binom(n-1,k-1) + binom(n-1,k)    
    
  end
  
  return pascals_triangle[n][k]
end

--BERNSTEIN BASIS POLYNOMIAL---------------------------
local function bern(val,v,n)

  return binom(n,v) * (val^v) * (1 - val)^(n-v)

end

--GET CURVE--------------------------------------
local function get_curve(t,points)
  
  --print("t: " .. t)
  
  local coords = {}  
  local numerators,denominators = {0,0},{0,0} --{x,y numerators}, {x,y denominators}
  local n = #points
  
  for j = 1, 2 do --run j loop once for x coords, once for y coords
    for i,point in ipairs(points)do --sum all of the points up with bernstein blending
      
      numerators[j] = numerators[j] + ( bern(t,i-1,n-1) * point[j] * point[3] )
      denominators[j] = denominators[j] + ( bern(t,i-1,n-1) * point[3] )
      
    end
    
    --print(j .. " numerator: " .. numerators[j])
    --print(j .. " denominator: " .. denominators[j])
    
    coords[j] = numerators[j]/denominators[j]
    
  end
  
  return coords
end

--INIT BUFFERS----------------------------
local function init_buffers()

  for x = 1, gridsize.x do
    if not buffer1[x] then buffer1[x] = {} end
    if not buffer2[x] then buffer2[x] = {} end
    for y = 1, gridsize.y do
      buffer1[x][y] = 0
      buffer2[x][y] = 0
    end
  end
end

--UPDATE CURVE GRID-------------------------------
local function update_curve_grid()
  
  --draw our line
  for x,column in ripairs(curvegrid) do
    for y,pixel in ipairs(column) do
      
      if buffer1[x][y] ~= buffer2[x][y] then
      
        pixel.bitmap = ("Bitmaps/%s.bmp"):format(tostring(buffer1[x][y]))
        
      end
      
    end
  end

end

--CALCULATE CURVE---------------------------------
local function calculate_curve()
  
  --store our buffer from last frame
  buffer2 = table.rcopy(buffer1)
  
  --clear buffer1 to all 0's
  for x = 1, gridsize.x do
    for y = 1, gridsize.y do
      buffer1[x][y] = 0
    end
  end
  
  table.clear(sampled_points)
  
  local samplesize = samplesize
  
  --find the x,y coords for each samplesize'd-increment of t along our curve
  for x = 1, samplesize do
    
    --get our t value
    local t = (x-1) / (samplesize-1)
    
    local coords = get_curve(t,points)
    
    --rprint(coords)
    
    sampled_points[x] = {coords[1],coords[2]}
    
    
  
  end

end

--REMAP RANGE-------------------------------------------------------
local function remap_range(val,lo1,hi1,lo2,hi2)

  return lo2 + (hi2 - lo2) * ((val - lo1) / (hi1 - lo1))

end

--SIGN------------------------------------
local function sign(number)
  return number > 0 and 1 or (number == 0 and 0 or -1)
end

--RASTERIZE CURVE------------------------------------
local function rasterize_curve()

  if draw_mode then
  
    for i = 1, #sampled_points - 1 do
    
      local coords = {sampled_points[i][1],sampled_points[i][2]}
  
      --convert from float in 0-1 range to integer in 1-gridsize range
      coords[1] = math.floor(coords[1] * (gridsize.x-1) + 1.5)
      
      --convert from float in 0-1 range to integer in 1-gridsize range
      coords[2] = math.floor(coords[2] * (gridsize.y-1) + 1.5)    
      
      if not (coords[1] < coords[1] - 1 and coords[2] < coords[2] - 1) then --nan check
        --add this pixel into our buffer
        if rainbow_mode then
          if use_x_rainbow then
            --draw our line rainbow according to x coordinates
            buffer1[coords[1]][coords[2]] = ("rainbow/" .. math.floor(remap_range(coords[1],1,gridsize.x,0,23)))
          else
            --draw our line rainbow according to t value
            buffer1[coords[1]][coords[2]] = ("rainbow/" .. math.floor(remap_range(i,1,#sampled_points,0,23)))
          end
        else
          --draw our line white
            buffer1[coords[1]][coords[2]] = 1
        end
      end
      
    end
  
  else

    for i = 1, #sampled_points - 1 do
    
      --print(i)
      
      local point_a, point_b, pixel_a, pixel_b = 
        { sampled_points[i][1], sampled_points[i][2] },
        { sampled_points[i+1][1], sampled_points[i+1][2] },
        {},
        {}
        
        
      --convert point_a from float in 0-1 range to float in 1-gridsize range
      point_a[1] = remap_range(point_a[1],0,1,1,gridsize.x)
      point_a[2] = remap_range(point_a[2],0,1,1,gridsize.y)
      
      --convert point_b from float in 0-1 range to float in 1-gridsize range
      point_b[1] = remap_range(point_b[1],0,1,1,gridsize.x)
      point_b[2] = remap_range(point_b[2],0,1,1,gridsize.y)
        
      --local floatslope = (point_b[2] - point_a[2]) / (point_b[1] - point_a[1]) --y/x
          
      --convert point_a from float to integer (pixel)
      pixel_a[1] = math.floor(point_a[1] + 0.5)
      pixel_a[2] = math.floor(point_a[2] + 0.5)
      
      --convert point_b from float to integer (pixel)
      pixel_b[1] = math.floor(point_b[1] + 0.5)
      pixel_b[2] = math.floor(point_b[2] + 0.5)
      
      local color
      if rainbow_mode and not use_x_rainbow then
        --draw our line rainbow according to t value
        color = ("rainbow/" .. math.floor(remap_range(i,1,#sampled_points,0,23)))
      else
        --draw our line white
          color = 1
      end
      
      --calculate the difference in our x and y coords from point b to point a
      local diff = { pixel_b[1]-pixel_a[1] , pixel_b[2]-pixel_a[2] }
      
      --find out which plane we will traverse by 1 pixel each loop iteration
      local plane
      if math.abs(diff[1]) >= math.abs(diff[2]) then
        --we want to traverse the x-plane
        plane = 1
      else
        --we want to traverse the y-plane
        plane = 2
      end
      
      --determine if we will be moving in positive or negative direction along plane
      local step = sign(diff[plane])
      
      --calculate our slope
      local slope = step * ((plane == 1 and diff[2]/diff[1]) or diff[1]/diff[2]) --(our slope is dependent on which plane we're on)
      
      local current_coords = {pixel_a[1],pixel_a[2]}
      local slope_acc = 0
      while(true) do
      
        if rainbow_mode and use_x_rainbow then
          --draw our line rainbow according to x coordinates
          buffer1[current_coords[1]][current_coords[2]] = 
            ("rainbow/" .. math.floor(remap_range(current_coords[1],1,gridsize.x,0,23)))
        else        
          buffer1[current_coords[1]][current_coords[2]] = color
        end
        
        if current_coords[plane] == pixel_b[plane] then break end --if we are at the end pixel, we break
        
        current_coords[plane] = current_coords[plane] + step
        slope_acc = slope_acc + slope
        current_coords[plane%2 + 1] = math.floor(pixel_a[plane%2 + 1] + slope_acc)
      
      end
      
    end
    
  end
  
  
  
        
  
end

--SHOW POINTS-----------------------------
local function show_points()

  for i,p in ipairs(points) do
    
    local point = {}
    --convert from float in 0-1 range to integer in 1-gridsize range
    point[1] = math.floor(p[1] * (gridsize.x-1) + 1.5)
    
    --convert from float in 0-1 range to integer in 1-gridsize range
    point[2] = math.floor(p[2] * (gridsize.y-1) + 1.5)
    
    --add this pixel into our buffer
    if rainbow_mode then
      
      --get the t value where this point exerts its influence on the line
      local t = (i-1) / (#points-1)
      
      --get the coordinates of where the line sits for that t value
      local coords = get_curve(t,points)

      --convert from float in 0-1 range to integer in 1-gridsize range
      coords[1] = math.floor(coords[1] * (gridsize.x-1) + 1.5)
      
      --convert from float in 0-1 range to integer in 1-gridsize range
      coords[2] = math.floor(coords[2] * (gridsize.y-1) + 1.5)
      
      if use_x_rainbow then
        --draw our point rainbow according to x coordinates
        buffer1[point[1]][point[2]] = ("rainbow/" .. math.floor((coords[1] * 23) / gridsize.x))
      else
        --draw our point rainbow according to t value
        buffer1[point[1]][point[2]] = ("rainbow/" .. math.floor(t * 23))
      end
        
    else
      --draw our point white
        buffer1[point[1]][point[2]] = 1
    end
    
    --draw a grey cross around our currently selected point
    if i == selectedpoint then
      if point[1] - 1 > 0 then buffer1[point[1] - 1][point[2]] = 0.25 end
      if point[1] + 1 < gridsize.x then buffer1[point[1] + 1][point[2]] = 0.25 end
      if point[2] - 1 > 0 then buffer1[point[1]][point[2] - 1] = 0.25 end
      if point[2] + 1 < gridsize.y then buffer1[point[1]][point[2] + 1] = 0.25 end
    end
    
  end

end

--SHOW GUIDES-----------------------------
local function show_guides()

  buffer1[math.floor((gridsize.x/2) + 0.5)][1] = 0.25
  buffer1[math.floor((gridsize.x/2) + 0.5)][gridsize.y] = 0.25
  buffer1[1][math.floor((gridsize.y/2) + 0.5)] = 0.25
  buffer1[gridsize.x][math.floor((gridsize.y/2) + 0.5)] = 0.25
  
  buffer1[math.floor((gridsize.x/2) + 0.5)][math.floor((gridsize.y/2) + 0.5)] = 0.25

end

--UPDATE TEXTS-----------------------------
local function update_texts()

  vb.views.sel_text.value = selectedpoint
  vb.views.x_text.value = points[selectedpoint][1]
  vb.views.y_text.value = points[selectedpoint][2]

end

--PROCESSING---------------------------------
local function processing()

  show_guides()

  calculate_curve()
  
  rasterize_curve()
  
  show_points()
          
  update_curve_grid()
  
  update_texts()

end

--APPLY UPDATE NOTIFIER----------------------------------
local function apply_update_notifier()

  processing()
  
  tool.app_idle_observable:remove_notifier(apply_update_notifier)
  
end

--QUEUE PROCESSING--------------------------------------
local function queue_processing()
  
  if not idle_processing then
    processing()
  else
    if not tool.app_idle_observable:has_notifier(apply_update_notifier) then
      tool.app_idle_observable:add_notifier(apply_update_notifier)
    end
  end
  
end

--FIND NEAREST POINT------------------------------------
local function find_nearest_point(x,y)
  
  --print("x: " .. x .. "  y: " .. y)
  
  local nearest_point = {5,0} --distance,index
  for k,point in ipairs(points) do
    
    local distance = math.abs(x - point[1]) + math.abs(y - point[2])
    
    --print("point: " .. k .. "   distance: " .. distance)
    
    if distance < nearest_point[1] then
      nearest_point[2] = k
      nearest_point[1] = distance
    end
    
  end
  
  return nearest_point[2]
end

--CREATE DIALOG----------------------------------------------------
local function create_dialog()
  
  if not window_content then
    window_content = vb:column {}
    
    local curvegridcontent = vb:row{
      spacing = -gridsize.x * 4,
      
      vb:xypad {
        width = gridsize.x * 4,
        height = gridsize.y * 4,
        value = {x = 0.5, y = 0.5},
        snapback = {x = 0.5, y = 0.5},
        notifier = function(value)
        
          if padreleased then
            
            if value.x ~= 0.5 then point_x = value.x end
            if value.y ~= 0.5 then point_y = value.y end
          
            if value.x ~= 0.5 and value.y ~= 0.5 then
              selectedpoint = find_nearest_point(point_x,point_y)
              
              padreleased = false
              --print("find_nearest_point")
              vb.views.slider.value = points[selectedpoint][3] - 1
            end            
          end
          
          if value.x == 0.5 or value.y == 0.5 then
            padreleased = true
            --print("padreleased!")
          else
            
            --print("processing")
            --set point to our xyPad coordinates
            points[selectedpoint][1] = value.x
            points[selectedpoint][2] = value.y
            
            queue_processing()
            
          end
        
        end
      }
      
    }
    
    local gridcolumn = vb:column{}
    local gridrow = vb:row {}
      
    --create our curve grid
    for x = 1, gridsize.x do 
      
      curvegrid[x] = {}  
          
      -- create a column
      local column = vb:column {}
    
      for y = 1, gridsize.y do    
          
        --fill the column with 16 pixels
        curvegrid[x][gridsize.y+1 - y] = vb:bitmap {
          bitmap = "Bitmaps/0.bmp",
          active = false          
        }
      
        -- add the pixel by "hand" into the row
        column:add_child(curvegrid[x][gridsize.y+1 - y])
    
      end
      
      gridrow:add_child(column) 
      
    end
    
    gridcolumn:add_child(gridrow)
    
    curvegridcontent:add_child(gridcolumn)
    
    window_content:add_child(curvegridcontent)
    
    
    local controlcolumn = vb:column {  
      
      vb:row {
        
        vb:valuefield {
          id = "sel_text",
          width = 16,
          tooltip = "Currently selected point",
          min = 1,
          max = 99,
          value = selectedpoint,
          
          --tonumber converts any typed-in user input to a number value 
          --(called only if value was typed)
          tonumber = function(str)
            local val = str:gsub("[^0-9.-]", "") --filter string to get numbers and decimals
            val = tonumber(val) --this tonumber() is Lua's basic string-to-number converter
            if val and 1 <= val then --if val is a number, and within min/max
              selectedpoint = val
              vb.views.slider.value = points[selectedpoint][3] - 1
              queue_processing()
            end
            return val
          end,
          
          --tostring is called when field is clicked, 
          --after tonumber is called,
          --and after the notifier is called
          --it converts the value to a formatted string to be displayed
          tostring = function(value)
            return ("%i"):format(value)
          end,        
          
          --notifier is called whenever the value is changed
          notifier = function(value)
          end
        },
        
        vb:minislider {
          id = "slider",
          tooltip = "Set the weight of the selected point",
          width = gridsize.x,
          height = 16,
          min = -1,
          max = 8,
          value = 0,
          notifier = function(value)
            
            points[selectedpoint][3] = value + 1
            
            queue_processing()
            
          end                      
        },
        
        vb:button {
          text = "+",
          tooltip = "Add a new control point after the currently selected control point",
          pressed = function()
            table.insert(points, math.floor(selectedpoint + 1), {0.5,0.5,1})
            selectedpoint = selectedpoint + 1
            queue_processing()
          end
        },
        
        vb:button {
          text = "-",
          tooltip = "Remove the currently selected control point",
          pressed = function()
            if #points > 2 then
              table.remove(points, selectedpoint)
              queue_processing()
            end
          end
        },
        
        vb:valuefield {
          id = "x_text",
          width = 32,
          tooltip = "X coordinate of the currently selected point",
          min = 0,
          max = 1,
          value = points[selectedpoint][1],
          
          --tonumber converts any typed-in user input to a number value 
          --(called only if value was typed)
          tonumber = function(str)
            local val = str:gsub("[^0-9.-]", "") --filter string to get numbers and decimals
            val = tonumber(val) --this tonumber() is Lua's basic string-to-number converter
            if val and 0 <= val and val <= 1 then --if val is a number, and within min/max
              --set point to our xyPad coordinates
              points[selectedpoint][1] = val
              queue_processing()
            end
            return val
          end,
          
          --tostring is called when field is clicked, 
          --after tonumber is called,
          --and after the notifier is called
          --it converts the value to a formatted string to be displayed
          tostring = function(value)
            return ("%.3f"):format(value)
          end,        
          
          --notifier is called whenever the value is changed
          notifier = function(value)
          end
        },
        
        vb:valuefield {
          id = "y_text",
          width = 32,
          tooltip = "Y coordinate of the currently selected point",
          min = 0,
          max = 1,
          value = points[selectedpoint][2],
          
          --tonumber converts any typed-in user input to a number value 
          --(called only if value was typed)
          tonumber = function(str)
            local val = str:gsub("[^0-9.-]", "") --filter string to get numbers and decimals
            val = tonumber(val) --this tonumber() is Lua's basic string-to-number converter
            if val and 0 <= val and val <= 1 then --if val is a number, and within min/max
              --set point to our xyPad coordinates
              points[selectedpoint][2] = val
              queue_processing()
            end
            return val
          end,
          
          --tostring is called when field is clicked, 
          --after tonumber is called,
          --and after the notifier is called
          --it converts the value to a formatted string to be displayed
          tostring = function(value)
            return ("%.3f"):format(value)
          end,        
          
          --notifier is called whenever the value is changed
          notifier = function(value)
          end
        }
        
      },
      
      vb:row {
        
        vb:checkbox {
          tooltip = "Rainbow Mode",
          value = rainbow_mode,      
          notifier = function(val)
            rainbow_mode = val
            queue_processing()
          end
        },
        
        vb:checkbox {
          tooltip = "True - Distribute rainbow across range of entire window based on X coordinate\nFalse - Distribute rainbow across range of the line segment fully",
          value = use_x_rainbow,      
          notifier = function(val)
            use_x_rainbow = val
            queue_processing()
          end
        },
        
        vb:checkbox {
        tooltip = "True - Offload processing to idle notifier\nFalse - Process changes immediately",
          value = idle_processing,      
          notifier = function(val)
            idle_processing = val
            queue_processing()
          end
        },
        
        vb:checkbox {
        tooltip = "Point Mode",
          value = draw_mode,      
          notifier = function(val)
            draw_mode = val
            queue_processing()
          end
        },
        
        vb:minislider {
          tooltip = "t sample size",
          width = gridsize.x,
          height = 16,
          min = 0,
          max = 524,
          value = 0,
          notifier = function(value)
            
            samplesize = math.floor(value + 1)
            print("samplesize: " .. samplesize)
            
            queue_processing()
            
          end                      
        }
      }
    }
    
    window_content:add_child(controlcolumn)

    
  end
    
  --key handler function
  local function key_handler(dialog,key)
  
    if key.state == "pressed" then
      
      if not key.repeated then
      
        if key.modifiers == "" then
          
        elseif key.modifiers == "shift" then
        
        elseif key.modifiers == "alt" then
        
        elseif key.modifiers == "control" then
        
        elseif key.modifiers == "shift + alt" then
        
        elseif key.modifiers == "shift + control" then
        
        elseif key.modifiers == "alt + control" then
        
        elseif key.modifiers == "shift + alt + control" then
        
        end
      
      elseif key.repeated then
      
        if key.modifiers == "" then
        
        elseif key.modifiers == "shift" then
        
        elseif key.modifiers == "alt" then
        
        elseif key.modifiers == "control" then
        
        elseif key.modifiers == "shift + alt" then
        
        elseif key.modifiers == "shift + control" then
        
        elseif key.modifiers == "alt + control" then
        
        elseif key.modifiers == "shift + alt + control" then
        
        end
      
      end --end if key.repeated
      
    elseif key.state == "released" then
    
      if key.modifiers == "" then
      
      elseif key.modifiers == "shift" then
      
      elseif key.modifiers == "alt" then
      
      elseif key.modifiers == "control" then
      
      elseif key.modifiers == "shift + alt" then
      
      elseif key.modifiers == "shift + control" then
      
      elseif key.modifiers == "alt + control" then
      
      elseif key.modifiers == "shift + alt + control" then
      
      end
      
    end --end if key.state == "pressed"/"released"
    
  end --end key_handler()
  
  --key handler options
  local key_handler_options = {
    send_key_repeat = true,
    send_key_release = true
  }
  
  --create the dialog if it show the dialog window
  if not window_obj or not window_obj.visible then
    window_obj = app:show_custom_dialog("Curves", window_content, key_handler, key_handler_options)
  else window_obj:show() end
  
end

--INIT TOOL--------------------------
local function init_tool()

  create_dialog()
  init_buffers()
  queue_processing()

end

--MENU ENTRIES----------------------------------------------------
renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:Curve Tests...",
  invoke = function() init_tool() end 
}

renoise.tool():add_keybinding {
  name = "Global:Tools:Curve Tests...",
  invoke = function() init_tool() end 
}
