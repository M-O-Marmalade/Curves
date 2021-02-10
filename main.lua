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
local points = { {0,1,1}, {1,0,1} } --x,y,weight
local selectedpoint = 1
local padreleased = true
local rainbow_mode = true
local use_x_rainbow = true
local idle_processing = false
local sample_size_multiplier = 1

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
  
  local samplesize = gridsize.x * sample_size_multiplier
  
  --find the x,y coords for each samplesize'd-increment of t along our curve
  for x = 1, samplesize do
    
    --get our t value
    local t = (x-1) / (samplesize-1)
    
    local coords = get_curve(t,points)
    
    --rprint(coords)
    
    --convert from float in 0-1 range to integer in 1-gridsize range
    coords[1] = math.floor(coords[1] * (gridsize.x-1) + 1.5)
    
    --convert from float in 0-1 range to integer in 1-gridsize range
    coords[2] = math.floor(coords[2] * (gridsize.y-1) + 1.5)
    
    --print(t)
    
    --print("coords[1]: " .. coords[1])
    --print("coords[2]: " .. coords[2])
    
    if not (coords[1] < coords[1] - 1 and coords[2] < coords[2] - 1) then --nan check
      --add this pixel into our buffer
      if rainbow_mode then
        if use_x_rainbow then
          --draw our line rainbow according to x coordinates
          buffer1[coords[1]][coords[2]] = ("rainbow/" .. math.floor((coords[1] * 23) / gridsize.x))
        else
          --draw our line rainbow according to t value
          buffer1[coords[1]][coords[2]] = ("rainbow/" .. math.floor(t * 23))
        end
      else
        --draw our line white
          buffer1[coords[1]][coords[2]] = 1
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
    
    buffer1[point[1]][point[2]] = 1
    
  end

end

--PROCESSING---------------------------------
local function processing()

  calculate_curve()
  
  show_points()
          
  update_curve_grid()
  
  vb.views.sel_text.text = tostring(selectedpoint)

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
  
  print("x: " .. x .. "  y: " .. y)
  
  local nearest_point = {5,0} --distance,index
  for k,point in ipairs(points) do
    
    local distance = math.abs(x - point[1]) + math.abs(y - point[2])
    
    print("point: " .. k .. "   distance: " .. distance)
    
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
    
    
    local controlrow = vb:row {  
      
      vb:text{
        id = "sel_text",
        text = "1",
      },
      
      vb:minislider {
        id = "slider",
        tooltip = "Set the weight of the selected point",
        width = gridsize.x,
        height = 16,
        min = -1,
        max = 4,
        value = 0,
        notifier = function(value)
          
          points[selectedpoint][3] = value + 1
          
          queue_processing()
          
        end                      
      },
      
      vb:button {
        text = "+",
        tooltip = "Add a new control point",
        pressed = function()
          table.insert(points, math.floor(#points/2 + 1), {0.5,0.5,1})
          queue_processing()
        end
      },
      
      vb:button {
        text = "-",
        tooltip = "Remove the currently selected control point",
        pressed = function()
          if #points > 1 then
            table.remove(points, selectedpoint)
            queue_processing()
          end
        end
      },
      
      vb:checkbox {
        tooltip = "Rainbow Mode",
        value = rainbow_mode,      
        notifier = function(val)
          rainbow_mode = val
          queue_processing()
        end
      },
      
      vb:checkbox {
        tooltip = "True - Distribute rainbow across range of the line segment fully\nFalse - Distribute rainbow across range of entire window based on X coordinate",
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
      
      vb:minislider {
        tooltip = "t sample size multiplier",
        width = gridsize.x / 1.5,
        height = 16,
        min = 0,
        max = 16,
        value = 0,
        notifier = function(value)
          
          sample_size_multiplier = value + 1
          
          queue_processing()
          
        end                      
      },
    }
    
    window_content:add_child(controlrow)

    
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
