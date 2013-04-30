--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "Selection BlurryHalo",
    desc      = "Shows a halo for selected and hovered units. (Doesn't work on ati cards!)",
    author    = "CarRepairer, from jK's gfx_halo",
    date      = "Jan, 2008",
    version   = "0.0001",
    license   = "GNU GPL, v2 or later",
    layer     = -10,
    enabled   = false  --  loaded by default?
  }
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local showAlly = false
local visibleAllySelUnits = {}
local visibleSelected = {}

options_path = 'Settings/Interface/Selection/Blurry Halo Selections'
options = {
	showally = {
		name = 'Show Ally Selections',
		type = 'bool',
		desc = 'Highlight in yellow the units your allies currently have selected.',
		value = true,
		OnChange = function(self) 
			visibleAllySelUnits = {}
			showAlly = self.value
		end,
	},
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--// user var

local gAlpha = 0.8

--// app var

local offscreentex
local depthtex
local blurtex
local fbo

local blurShader_h
local blurShader_v
local uniformScreenX, uniformScreenY

local vsx, vsy = 0,0
local resChanged = false


--more
local featureHoverColor = { 1, 0, 1 }
local myHoverColor 	    = { 0, 1, 1 }
local allyHoverColor 	= { 0.2, 0.2, 1 }
local enemyHoverColor   = { 1, 0, 0 }
local selectColor 	    = { 0, 1, 0 }
local allySelectColor 	= { 1, 1, 0 }

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--// gl const

local GL_DEPTH_BITS = 0x0D56

local GL_DEPTH_COMPONENT   = 0x1902
local GL_DEPTH_COMPONENT16 = 0x81A5
local GL_DEPTH_COMPONENT24 = 0x81A6
local GL_DEPTH_COMPONENT32 = 0x81A7

local GL_COLOR_ATTACHMENT0_EXT = 0x8CE0
local GL_COLOR_ATTACHMENT1_EXT = 0x8CE1
local GL_COLOR_ATTACHMENT2_EXT = 0x8CE2
local GL_COLOR_ATTACHMENT3_EXT = 0x8CE3

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--// speed ups

local ALL_UNITS       = Spring.ALL_UNITS

local spGetMyTeamID     = Spring.GetMyTeamID
local spGetUnitTeam     = Spring.GetUnitTeam
local spValidUnitID		= Spring.ValidUnitID
local ValidFeatureID	= Spring.ValidFeatureID
local spIsUnitAllied	= Spring.IsUnitAllied
local spIsUnitSelected	= Spring.IsUnitSelected
local spGetMouseState	= Spring.GetMouseState
local spTraceScreenRay	= Spring.TraceScreenRay
local spGetPlayerControlledUnit		= Spring.GetPlayerControlledUnit
local spGetVisibleUnits			= Spring.GetVisibleUnits

--local myPlayerID = Spring.GetMyPlayerID()

local GL_FRONT = GL.FRONT
local GL_BACK  = GL.BACK
local GL_MODELVIEW  = GL.MODELVIEW
local GL_PROJECTION = GL.PROJECTION
local GL_COLOR_BUFFER_BIT = GL.COLOR_BUFFER_BIT

local glUnit            = gl.Unit
local glFeature         = gl.Feature
local glCopyToTexture   = gl.CopyToTexture
local glRenderToTexture = gl.RenderToTexture
local glCallList        = gl.CallList
local glActiveFBO       = gl.ActiveFBO

local glUseShader  = gl.UseShader
local glUniform    = gl.Uniform
local glUniformInt = gl.UniformInt

local glClear     = gl.Clear
local glTexRect   = gl.TexRect
local glColor     = gl.Color
local glTexture   = gl.Texture
local glCulling   = gl.Culling
local glDepthTest = gl.DepthTest

local glResetMatrices = gl.ResetMatrices
local glMatrixMode    = gl.MatrixMode
local glPushMatrix    = gl.PushMatrix
local glLoadIdentity  = gl.LoadIdentity
local glPopMatrix     = gl.PopMatrix

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--functions


local function GetVisibleUnits()
    local units = spGetVisibleUnits(-1, 30, true)
    
	local visibleAllySelUnits = {}
    local visibleSelected = {}
    
    for i=1, #units do
	    local unitID = units[i]
	    if (spIsUnitSelected(unitID)) then
		    visibleSelected[#visibleSelected+1] = unitID
	    elseif showAlly and WG.allySelUnits[unitID] then
		    visibleAllySelUnits[#visibleAllySelUnits+1] = unitID
	    end
    end
    
    return visibleAllySelUnits, visibleSelected

end


local function DrawHaloFunc()
	visibleAllySelUnits, visibleSelected = GetVisibleUnits()

	glColor(selectColor)
	for i=1,#visibleSelected do
		local unitID = visibleSelected[i]
		glUnit(unitID,true)
	end
    
	glColor(allySelectColor)
	for i=1,#visibleAllySelUnits do
		local unitID = visibleAllySelUnits[i]
		glUnit(unitID,true)
	end
    
	local mx, my = spGetMouseState()
    local pointedType, data = spTraceScreenRay(mx, my)
	if pointedType == 'unit' and spValidUnitID(data) then
		local teamID = spGetUnitTeam(data)
		if teamID == spGetMyTeamID() then
			glColor(myHoverColor)
		elseif (teamID and Spring.AreTeamsAllied(teamID, Spring.GetMyTeamID()) ) then
			glColor(allyHoverColor)
		else
			glColor(enemyHoverColor)
		end
		
		glUnit(data, true)
    elseif (pointedType == 'feature') and ValidFeatureID(data) then
		glColor(featureHoverColor)
		glFeature(data, true)
    end
  
end


local DrawVisibleUnits

DrawVisibleUnits = DrawHaloFunc

local MyDrawVisibleUnits = function()
  glClear(GL_COLOR_BUFFER_BIT,0,0,0,0)
  --glCulling(GL_FRONT)
  DrawVisibleUnits()
  --glCulling(GL_BACK)
  --glCulling(false)
  glColor(1,1,1,1)
end
local blur_h = function()
  glClear(GL_COLOR_BUFFER_BIT,0,0,0,0)
  glUseShader(blurShader_h)
  glTexRect(-1-0.25/vsx,1+0.25/vsy,1+0.25/vsx,-1-0.25/vsy)
  --glTexRect(-1-1/vsx,1+1/vsy,1+1/vsx,-1-1/vsy)
end
local blur_v = function()
  --glClear(GL_COLOR_BUFFER_BIT,0,0,0,0)
  glUseShader(blurShader_v)
  glTexRect(-1-0.25/vsx,1+0.25/vsy,1+0.25/vsx,-1-0.25/vsy)
  --glTexRect(-1-1/vsx,1+1/vsy,1+1/vsx,-1-1/vsy)
end

function widget:DrawWorldPreUnit()
  glCopyToTexture(depthtex, 0, 0, 0, 0, vsx, vsy)

  if (resChanged) then
    resChanged = false
    if (vsx==1) or (vsy==1) then return end
     glUseShader(blurShader_h)
    glUniformInt(uniformScreenX,  math.ceil(vsx*0.5) )
     glUseShader(blurShader_v)
    glUniformInt(uniformScreenY,  math.ceil(vsy*0.5) )
  end

  glDepthTest(true)
  glActiveFBO(fbo,MyDrawVisibleUnits)
  glDepthTest(false)

  glTexture(offscreentex)
  glRenderToTexture(blurtex, blur_h)
  glTexture(blurtex)
  glRenderToTexture(offscreentex, blur_v)
  glColor(1,1,1,gAlpha)

  glCallList(enter2d)
  glTexture(offscreentex)
  glTexRect(-1-0.5/vsx,1+0.5/vsy,1+0.5/vsx,-1-0.5/vsy)
  glCallList(leave2d)
end


local function ShowSelectionSquares(state)
  local alpha = state and 1 or 0
  local f = io.open('cmdcolors.tmp', 'w+')
  if (f) then
    f:write('unitBox  0 1 0 ' .. alpha)
    f:close()
    Spring.SendCommands({'cmdcolors cmdcolors.tmp'})
  end
  os.remove('cmdcolors.tmp')
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--call ins

function widget:Initialize()
	showAlly = options.showally.value 
	
  if (not gl.CreateShader)or(not gl.CreateFBO) then
    Spring.Echo("Halo widget: your card is unsupported!")
    widgetHandler:RemoveWidget()
    return
  end

  vsx, vsy = widgetHandler:GetViewSizes()

  blurShader_h = gl.CreateShader({
    fragment = [[
      float kernel[7]; // = float[7]( 0.013, 0.054, 0.069, 0.129, 0.212, 0.301, 0.372);
      uniform sampler2D tex0;
      uniform int screenX;

      void InitKernel(void) {
        kernel[0] = 0.013;
        kernel[1] = 0.054;
        kernel[2] = 0.069;
        kernel[3] = 0.129;
        kernel[4] = 0.212;
        kernel[5] = 0.301;
        kernel[6] = 0.372;
      }

      void main(void) {
        InitKernel();

        int n;
        float pixelsize = 1.0/float(screenX);

        gl_FragColor = 0.4 * texture2D(tex0, gl_TexCoord[0].st );

        vec2 tc1 = gl_TexCoord[0].st;
        vec2 tc2 = gl_TexCoord[0].st;

        for(n=6; n>= 0; --n){
          tc1.s += pixelsize;
          tc2.s -= pixelsize;
          gl_FragColor += kernel[n] * ( texture2D(tex0, tc1 )+texture2D(tex0, tc2 ) );
        }
      }
    ]],
    uniformInt = {
      tex0 = 0,
      screenX = math.ceil(vsx*0.5),
    },
  })


  if (blurShader_h == nil) then
    Spring.Log(widget:GetInfo().name, LOG.ERROR, "Halo widget: hblur shader error: "..gl.GetShaderLog())
    widgetHandler:RemoveWidget()
    return false
  end

  blurShader_v = gl.CreateShader({
    fragment = [[
      float kernel[7]; // = float[7]( 0.013, 0.054, 0.069, 0.129, 0.212, 0.301, 0.372);
      uniform sampler2D tex0;
      uniform int screenY;

      void InitKernel(void) {
        kernel[0] = 0.013;
        kernel[1] = 0.054;
        kernel[2] = 0.069;
        kernel[3] = 0.129;
        kernel[4] = 0.212;
        kernel[5] = 0.301;
        kernel[6] = 0.372;
      }

      void main(void) {
        InitKernel();

        int n;
        float pixelsize = 1.0/float(screenY);

        gl_FragColor = 0.4 * texture2D(tex0, gl_TexCoord[0].st );

        vec2 tc1 = gl_TexCoord[0].st;
        vec2 tc2 = gl_TexCoord[0].st;

        for(n=6; n>= 0; --n){
          tc1.t += pixelsize;
          tc2.t -= pixelsize;
          gl_FragColor += kernel[n] * ( texture2D(tex0, tc1 )+texture2D(tex0, tc2 ) );
        }
      }
    ]],
    uniformInt = {
      tex0 = 0,
      screenY = math.ceil(vsy*0.5),
    },
  })

  if (blurShader_v == nil) then
    Spring.Log(widget:GetInfo().name, LOG.ERROR, "Halo widget: vblur shader error: "..gl.GetShaderLog())
    widgetHandler:RemoveWidget()
    return false
  end

  uniformScreenX  = gl.GetUniformLocation(blurShader_h, 'screenX')
  uniformScreenY  = gl.GetUniformLocation(blurShader_v, 'screenY')

  fbo = gl.CreateFBO()

  self:ViewResize(vsx,vsy)

  enter2d = gl.CreateList(function()
    glUseShader(0)
    glMatrixMode(GL_PROJECTION); glPushMatrix(); glLoadIdentity()
    glMatrixMode(GL_MODELVIEW);  glPushMatrix(); glLoadIdentity()
  end)
  leave2d = gl.CreateList(function()
    glMatrixMode(GL_PROJECTION); glPopMatrix()
    glMatrixMode(GL_MODELVIEW);  glPopMatrix()
    glTexture(false)
    glUseShader(0)
  end)
  
  
  ShowSelectionSquares(false)
end --init

function widget:ViewResize(viewSizeX, viewSizeY)
  vsx = viewSizeX
  vsy = viewSizeY

  fbo.color0 = nil

  gl.DeleteTexture(depthtex or 0)
  gl.DeleteTextureFBO(offscreentex or 0)
  gl.DeleteTextureFBO(blurtex or 0)

  depthtex = gl.CreateTexture(vsx,vsy, {
    border = false,
    format = GL_DEPTH_COMPONENT24,
    min_filter = GL.NEAREST,
    mag_filter = GL.NEAREST,
  })

  offscreentex = gl.CreateTexture(vsx,vsy, {
    border = false,
    min_filter = GL.LINEAR,
    mag_filter = GL.LINEAR,
    wrap_s = GL.CLAMP,
    wrap_t = GL.CLAMP,
    fbo = true,
  })

  blurtex = gl.CreateTexture(math.floor(vsx*0.5),math.floor(vsy*0.5), {
    border = false,
    min_filter = GL.LINEAR,
    mag_filter = GL.LINEAR,
    wrap_s = GL.CLAMP,
    wrap_t = GL.CLAMP,
    fbo = true,
  })

  fbo.depth  = depthtex
  fbo.color0 = offscreentex
  fbo.drawbuffers = GL_COLOR_ATTACHMENT0_EXT

  resChanged = true
end


function widget:Shutdown()
  gl.DeleteTexture(depthtex)
  if (gl.DeleteTextureFBO) then
    gl.DeleteTextureFBO(offscreentex)
    gl.DeleteTextureFBO(blurtex)
  end

  if (gl.DeleteFBO) then
    gl.DeleteFBO(fbo or 0)
  end

  if (gl.DeleteShader) then
    gl.DeleteShader(blurShader_h or 0)
    gl.DeleteShader(blurShader_v or 0)
  end

  gl.DeleteList(enter2d)
  gl.DeleteList(leave2d)
  
    ShowSelectionSquares(true)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
