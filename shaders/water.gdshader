/******************************************************************************
WATER SHADER - Rivers, Lakes, and Ocean Surfaces

Source: GodotShaders.com community shader
License: CC0 / MIT (check original source)

# Overview
Full-featured water shader with waves, foam, caustics, and shore effects.
Suitable for oceans, rivers, lakes, ponds, and waterfalls.

# Required Global Uniforms
The following global uniforms enhance water appearance:
- OceanWavesGradient: Optional wave height texture

# Key Features
- Animated waves (vertex displacement)
- Shore foam with texture
- Underwater caustics
- Depth-based transparency
- Screen-space distortion/refraction
- Normal map animation

# Parameter Groups
## Water Colors
- deep_color: Deep water tint
- shallow_color: Shallow water tint
- foam_color: Foam/whitecap color

## Waves
- wave_speed: Animation speed
- wave_scale: Wave frequency
- wave_height: Vertex displacement amount

## Foam
- enable_foam: Show shore foam
- foam_amount: Foam coverage
- foam_texture: Foam pattern texture

## Caustics
- enable_caustics: Underwater light patterns
- caustics_scale: Pattern size
- caustics_speed: Animation speed
- caustics_flipbook: Animated caustics texture

## Shore
- shore_depth: Shallow water threshold
- shore_fade: Edge fade distance

# Usage Notes
- Requires proper depth texture setup in Godot
- Wave height affects collision - match with CollisionShape
- Caustics need a texture flipbook for animation
- Foam shows where water meets geometry

# See Also
- docs/shader-reference.md for full parameter list
- docs/api/constants.md for Unity property mappings

# Original Implementation Notes
Water = Synty models water shader for Godot.
(C) Copyright 2025 - Giancarlo Niccolai
Published under MIT licence.
v 1.1

This shader is a Godot replacement for the Synty "Water" shader (october 2025).
Care has been taken to reproduce all the features of the original Water shader,
and reproduce similar visuals (including noise and wind effect) for similar
settings as close as possible.

However, some differences in the rendering pipeline has required slightly
different visuals for _distortion_ and for the _oceanic wave_ mesh displacing.

The options are organised following the same grouping and order of the
Unity Water Shader provided by Synty.

# Set up

This shader uses the global weather system provided by Synty asset packages;
in particular, it is necessary to set the following variables as global
shader variables in the host project:

- float GaleStrength: base wind power, will increase the wave height.
- vec3 WindDirection: direction pushing the waves; only X/Z normal is considered.
- sampler2D OceanWavesGradient: A texture2D used to displace the mesh to emulate
  oceanic waves.

The wave gradient should be a FastNoise or a 2-directional gradient; a
mono-directional gradient will limit the ability to rotate the wind direction.

This Godot shader has the ability to use non-global versions of the above
variables, de-activating the flag **use_global_weather_control**, which is
active by default.

# Improved settings

- ocean_wave_frequency zooms in the wave gradient/noise, reducing the
  size of the waves while maintaining their height and speed.
- maximum_depth cuts the depth at which water becomes completely opaque.
  The Synty package has a fixed constant set to 15 meters, which is
  the default for the setting in this shader.
- distortion_speed works with distortion_size to add a wavy look
  to underwater distortions.

# Main Visual Differences

- The wave generator has a slightly different logic, due to a different
  rendering pipeline in Godot. Given similar gradients, the waves should
  look similar, but you may need to tweak the values a bit.

- The _distortion_ effect uses a slightly different algorithm; it provides
  a nice distorting visual, but it will probably look different than on
  Unity.

- The oceanic wave foam may look a little bit sparser than on Unity, you
  may want to tweak the values.

- Normals are less defined than on Unity; as the reflection isn't as
  clear.

# Note

- Distortion hijacks the alpha setting, applying a manual transparency.
  The effects of borders _colorization_ (shallow, deep, very deep colors)
  are not taken in consideration when distorting, so, for credible results,
  use moderate settings both for colorization and distortion when used
  together.
******************************************************************************/

shader_type spatial;
render_mode blend_mix, depth_draw_always, diffuse_lambert, specular_schlick_ggx, cull_disabled; //  no depth_draw_opaque or cull_back but idk about diffuse_lambert, specular_disabled;

uniform bool _Enable_Shore_Wave_Foam = false;
uniform bool _Enable_Shore_Animation = true;
uniform float _Animation_Offset = 0.0;
uniform float _Shore_Edge_Opacity : hint_range(0.0, 1.0) = 1.0;
uniform float _Shore_Edge_Thickness : hint_range(0.0, 1.0) = 0.25;
uniform float _Shore_Edge_Noise_Scale = 0.1;
uniform float _Shore_Wave_Speed : hint_range(0.0, 1.0) = 0.3;
uniform float _Shore_Wave_Return_Amount : hint_range(0.0, 1.0) = 0.5;
uniform float _Shore_Wave_Thickness : hint_range(0.0, 1.0) = 0.25;

uniform bool _Enable_Shore_Foam = true;
uniform float _Shore_Foam_Noise_Scale = 1.0;
uniform sampler2D _Shore_Foam_Noise_Texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float _Shore_Small_Foam_Opacity : hint_range(0.0, 1.0) = 0.3;
uniform float _Shore_Small_Foam_Tiling = 0.03;

uniform vec4 _Shore_Wave_Color_Tint : source_color = vec4(0.5, 0.75, 0.86, 0.8);
uniform vec4 _Shore_Foam_Color_Tint : source_color = vec4(0.5, 0.75, 0.86, 0.8);

uniform float _Smoothness : hint_range(0.0, 1.0) = 0.8;
uniform float _Metallic : hint_range(0.0, 1.0) = 0.0;
uniform float _Base_Opacity : hint_range(0.0, 1.0) = 1.0;
uniform float _Shallows_Opacity : hint_range(0.0, 1.0) = 0.5;

uniform vec4 _Foam_Color : source_color = vec4(1.0, 1.0, 1.0, 0.8);
uniform vec4 _Shallow_Color : source_color = vec4(0.9529412, 0.7882353, 0.5882353, 0.8);
uniform vec4 _Deep_Color : source_color = vec4(0.07450981, 0.4313726, 0.4, 0.8);
uniform vec4 _Very_Deep_Color : source_color = vec4(0.01176471, 0.172549, 0.2745098, 0.8);
uniform float _Deep_Height = 15.0;
uniform float _Very_Deep_Height = 0.5;

uniform bool _Enable_Normals = true;
uniform sampler2D _Normal_Texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec2 _Normal_Offset = vec2(0.0, 0.0);
uniform float _Normal_Tiling = 0.01;
uniform float _Normal_Intensity : hint_range(0.0, 1.0) = 1.0;
uniform float _Normal_Pan_Speed = 1.0;
uniform float _Normal_Noise_Tiling = 1.0;
uniform float _Normal_Noise_Intensity = 1.0;

uniform bool _Enable_Fresnel_Fade = true;
uniform float _Fade_Distance = 1.0;
uniform float _Fade_Power = 0.0;

uniform bool _Enable_Ocean_Wave = false;
uniform float _Ocean_Wave_Height : hint_range(0.0, 10.0) = 1.0;
uniform float _Ocean_Wave_Speed : hint_range(0.0, 1.0) = 0.5;
uniform float _Ocean_Foam_Amount : hint_range(0.0, 1.0) = 0.5;
uniform float _Ocean_Foam_Opacity : hint_range(0.0, 1.0) = 0.4;
uniform float _Ocean_Foam_Breakup_Tiling = 1.0;

uniform bool _Enable_Caustics = true;
uniform float _Caustics_Scale = 15.0;
uniform bool _Caustics_Use_Voronoi_Noise = true;
uniform vec4 _Caustics_Color : source_color = vec4(0.7529412, 0.7333333, 0.6509804, 0.9);
uniform float _Caustics_Intensity : hint_range(0.0, 1.0) = 0.2;
uniform float _Caustics_Speed = 10.0;

uniform bool _Enable_Top_Scrolling_Texture = true;
uniform vec2 _Scrolling_Texture_Direction = vec2(0.0, -0.5);
uniform sampler2D _Scrolling_Texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec2 _Scrolling_Texture_Tiling = vec2(1.0, 1.0);
uniform vec4 _Scrolling_Texture_Tint : source_color = vec4(0.3712175, 0.7245609, 0.8113208, 0.8);
uniform float _Scrolling_Texture_Opacity : hint_range(0.0, 1.0) = 0.2;

uniform bool _Enable_Global_Foam = false;
uniform sampler2D _Noise_Texture : hint_default_white, filter_linear_mipmap_anisotropic;

uniform bool _Enable_Distortion = false;
uniform float _Distortion_Speed = 0.2;
uniform vec2 _Distortion_Direction = vec2(0.1, 0.1);
uniform float _Distortion_Strength = 0.06;
uniform float _Distortion_Size = 10.0;

uniform sampler2D _SampleTexture2D : hint_default_white, filter_linear_mipmap_anisotropic;

// System Textures
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// Hardcoded external variables from Unity SG
uniform vec3 _WindDirection = vec3(1.0, 0.0, 1.0);
uniform float _GaleStrength = 1.0;

// =========================================
// 2. HELPER FUNCTIONS
// =========================================

float remap(float value, vec2 inMinMax, vec2 outMinMax) {
    return outMinMax.x + (value - inMinMax.x) * (outMinMax.y - outMinMax.x) / (inMinMax.y - inMinMax.x);
}

vec3 rotate_about_axis(vec3 In, vec3 axis, float rotation_degrees) {
    float rot_rad = radians(rotation_degrees);
    float s = sin(rot_rad);
    float c = cos(rot_rad);
    vec3 ax = normalize(axis);
    return In * c + cross(ax, In) * s + ax * dot(ax, In) * (1.0 - c);
}

// Reconstructed Gradients from HLSL Arrays
vec4 sample_ocean_wave_gradient(float t) {
    if (t < 0.5) return mix(vec4(0.0), vec4(1.0, 1.0, 1.0, 0.5000076), t / 0.5);
    return mix(vec4(1.0, 1.0, 1.0, 0.5000076), vec4(0.0, 0.0, 0.0, 1.0), (t - 0.5) / 0.5);
}

vec4 sample_deep_fade_gradient(float t) {
    return mix(vec4(1.0, 1.0, 1.0, 0.8), vec4(0.0, 0.0, 0.0, 1.0), t);
}

vec4 sample_very_deep_fade_gradient(float t) {
    if (t < 0.5) return mix(vec4(0.0), vec4(1.0, 1.0, 1.0, 0.5000076), t / 0.5);
    return mix(vec4(1.0, 1.0, 1.0, 0.5000076), vec4(1.0), (t - 0.5) / 0.5);
}

vec2 unity_voronoi_random(vec2 UVxx, float offset) {
    mat2 m = mat2(vec2(15.27, 47.63), vec2(99.41, 89.98));
    vec2 r = fract(sin(UVxx * m) * 46839.32);
    return vec2(sin(r.y * offset), cos(r.x * offset)) * 0.5 + 0.5;
}

void unity_voronoi(vec2 UVxx, float AngleOffset, float CellDensity, out float Out, out float Cells) {
    vec2 g = floor(UVxx * CellDensity);
    vec2 f = fract(UVxx * CellDensity);
    float res_x = 8.0;
    float res_y = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 lattice = vec2(float(x), float(y));
            vec2 offset = unity_voronoi_random(lattice + g, AngleOffset);
            float d = distance(lattice + offset, f);
            if (d < res_x) {
                res_x = d;
                res_y = offset.x;
            }
        }
    }
    Out = res_x;
    Cells = res_y;
}

vec2 unity_gradient_noise_dir(vec2 p) {
    p = mod(p, 289.0);
    float x = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
    return normalize(vec2(x - floor(x + 0.5), abs(x) - 0.5));
}

float unity_gradient_noise(vec2 UVxx, float Scale) {
    vec2 p = UVxx * Scale;
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    float d00 = dot(unity_gradient_noise_dir(ip), fp);
    float d01 = dot(unity_gradient_noise_dir(ip + vec2(0.0, 1.0)), fp - vec2(0.0, 1.0));
    float d10 = dot(unity_gradient_noise_dir(ip + vec2(1.0, 0.0)), fp - vec2(1.0, 0.0));
    float d11 = dot(unity_gradient_noise_dir(ip + vec2(1.0, 1.0)), fp - vec2(1.0, 1.0));
    fp = fp * fp * fp * (fp * (fp * 6.0 - 15.0) + 10.0);
    return mix(mix(d00, d10, fp.x), mix(d01, d11, fp.x), fp.y) + 0.5;
}

vec2 unity_flipbook(vec2 UVxx, float Width, float Height, float Tile, vec2 Invert) {
    Tile = floor(mod(Tile + 0.00001, Width * Height));
    vec2 tileCount = vec2(1.0, 1.0) / vec2(Width, Height);
    float base = floor((Tile + 0.5) * tileCount.x);
    float tileX = (Tile - Width * base);
    float tileY = (Invert.y * Height - (base + Invert.y * 1.0));
    return (UVxx + vec2(tileX, tileY)) * tileCount;
}

vec4 top_down_projection(sampler2D tex, vec2 tiling, vec2 offset, vec3 world_normal, vec3 abs_world_pos) {
    vec3 sgn = sign(world_normal);
    vec3 mul1 = sgn * vec3(-1.0, 1.0, 1.0);
    vec2 rg = vec2(mul1.y, 1.0);
    vec3 mul3 = abs_world_pos * vec3(1.0, 1.0, -1.0);
    vec2 vec2_mul = vec2(mul3.x, mul3.z);
    vec2 final_uv = rg * vec2_mul;
    return texture(tex, final_uv * tiling + offset);
}

vec4 top_down_projection_normal(sampler2D tex, vec2 tiling, vec2 offset, vec3 world_normal, vec3 abs_world_pos) {
    vec4 t = top_down_projection(tex, tiling, offset, world_normal, abs_world_pos);
    t.rgb = t.rgb * 2.0 - 1.0; // Unpack Godot NORMAL hint to -1..1 logic
    return t;
}

// =========================================
// 3. VERTEX FUNCTION
// =========================================

varying vec3 var_AbsoluteWorldSpacePosition;
varying vec3 var_WorldNormal;

void vertex() {
    var_AbsoluteWorldSpacePosition = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    var_WorldNormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    
    // SG_OceanWaveMask Logic
    float owm_saturate = clamp(_GaleStrength, 0.0, 1.0);
    float owm_add1 = owm_saturate + 1.5;
    float owm_mult1 = (_Ocean_Wave_Speed * 10.0) * TIME;
    
    vec3 wind_norm = normalize(_WindDirection);
    float dot_p = clamp(dot(wind_norm, vec3(0.0, 0.0, 1.0)), -1.0, 1.0);
    float acos_val = degrees(acos(dot_p));
    float owm_branch = (wind_norm.x >= 0.0) ? (1.0 - acos_val) : acos_val;
    
    vec3 rotated_pos = rotate_about_axis(var_AbsoluteWorldSpacePosition, vec3(0.0, 1.0, 0.0), owm_branch + 225.0);
    float wave_frac = fract((rotated_pos.x + rotated_pos.z + owm_mult1) * 0.01);
    
    vec4 grad_out = sample_ocean_wave_gradient(wave_frac);
    float wave_mult_final = (grad_out.r + grad_out.g) * _Ocean_Wave_Height * (grad_out.r + grad_out.g);
    
    vec3 wave_offset = vec3(grad_out.r, wave_mult_final, grad_out.b);
    vec3 offset_sub = wave_offset - vec3(_Ocean_Wave_Height / 2.0);
    
    // In Unity, this subgraph output replaces the Object Space Position (effectively acting as an offset in World Space in most setups)
    if (_Enable_Ocean_Wave) {
        VERTEX += offset_sub; // Apply relative offset per Rule 4
    }
}

// =========================================
// 4. FRAGMENT FUNCTION
// =========================================

void fragment() {
    vec3 AbsoluteWorldSpacePosition = var_AbsoluteWorldSpacePosition;
    vec3 WorldNormal = normalize(var_WorldNormal);
    vec3 ViewDir = normalize(CAMERA_POSITION_WORLD - AbsoluteWorldSpacePosition);
    
    // Seafloor Reconstruction & Depth Delta (Rule 5)
    float depth_tex = texture(depth_texture, SCREEN_UV).x;
    vec3 ndc_pos = vec3(SCREEN_UV * 2.0 - 1.0, depth_tex);
    vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc_pos, 1.0);
    view_pos.xyz /= view_pos.w;
    
    float scene_depth_eye = -view_pos.z;
    float surface_depth_eye = -(VIEW_MATRIX * vec4(AbsoluteWorldSpacePosition, 1.0)).z;
    float depth_fade = max(0.0, scene_depth_eye - surface_depth_eye);
    
    // -----------------------------------------
    // Top Scrolling Texture
    // -----------------------------------------
    vec2 scroll_uv = (AbsoluteWorldSpacePosition.xz * 0.1) + (1.0 - (_Scrolling_Texture_Direction * TIME * 0.2));
    vec4 scroll_tex = texture(_Scrolling_Texture, scroll_uv * _Scrolling_Texture_Tiling);
    vec4 scroll_final = _Enable_Top_Scrolling_Texture ? (scroll_tex * _Scrolling_Texture_Tint * _Scrolling_Texture_Opacity) : vec4(0.0);
    
    // -----------------------------------------
    // Water Color Gradients
    // -----------------------------------------
    float deep_fade_sat = clamp(depth_fade / abs(_Deep_Height), 0.0, 1.0);
    vec4 deep_grad = sample_deep_fade_gradient(deep_fade_sat);
    vec4 color_deep = mix(_Shallow_Color, _Deep_Color, deep_grad);
    
    float very_deep_fade_sat = clamp(depth_fade / abs(_Very_Deep_Height), 0.0, 1.0);
    vec4 very_deep_grad = sample_very_deep_fade_gradient(very_deep_fade_sat);
    vec4 color_very_deep = mix(color_deep, _Very_Deep_Color, very_deep_grad);
    
    // -----------------------------------------
    // Caustics
    // -----------------------------------------
    float caustics_int = remap(_Caustics_Intensity, vec2(0.0, 1.0), vec2(0.0, 10.0));
    float caustics_dot = dot(ViewDir, (INV_VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
    caustics_dot = sign(caustics_dot) * max(abs(caustics_dot), 0.00001);
    
    float max_caustics_depth = 5.0; 
    float caustics_depth_fade = min(depth_fade, max_caustics_depth);
    float caustics_scene_depth_eye = surface_depth_eye + caustics_depth_fade;

    // Use our capped scene depth for the UV projection so the texture doesn't stretch over the void
    vec3 caustics_proj = caustics_scene_depth_eye * (ViewDir / caustics_dot) + CAMERA_POSITION_WORLD;
    vec2 caustics_uv = vec2(caustics_proj.x, caustics_proj.z);
    
    float voronoi_time = (TIME + 100.0) * 2.0;
    float v_out, v_cells;
    unity_voronoi(caustics_uv, voronoi_time, 3.0, v_out, v_cells);
    float v_pow = clamp(pow(v_out, 4.0), 0.0, 1.0);
    
    vec2 c_frac = fract(caustics_uv / max(_Caustics_Scale, 0.01));
    float c_speed = remap(_Caustics_Speed, vec2(0.0, 1.0), vec2(0.0, 10.0));
    vec2 c_flipbook = unity_flipbook(c_frac, 8.0, 8.0, floor(TIME * c_speed), vec2(0.0, 1.0));
    vec4 c_tex = texture(_SampleTexture2D, c_flipbook);
    
    float c_branch = _Caustics_Use_Voronoi_Noise ? v_pow : c_tex.r;
    
    // FIX: Use our clamped caustics_depth_fade here so opacity remains constant over the void
    float c_depth_sat = clamp(caustics_depth_fade * 0.1, 0.0, 1.0);
    float c_depth_mask = (1.0 - c_depth_sat) * c_depth_sat;
    vec4 caustics_final = _Enable_Caustics ? (vec4(c_branch) * c_depth_mask * _Caustics_Color * clamp(caustics_int, 0.0, 1.0)) : vec4(0.0);
    // -----------------------------------------
    // Shore Animations & Waves
    // -----------------------------------------
    float shore_anim = _Enable_Shore_Animation ? TIME : _Animation_Offset;
    vec4 shore_noise = top_down_projection(_Noise_Texture, vec2(_Shore_Edge_Noise_Scale * 0.005), vec2(0.0), WorldNormal, AbsoluteWorldSpacePosition);
    
    float shore_mod = mod(((shore_anim * _Shore_Wave_Speed) + clamp(shore_noise.r, 0.0, 1.0)), 1.0);
    float shore_sine = sin(shore_mod * (3.141593 / remap(_Shore_Wave_Return_Amount, vec2(0.0, 1.0), vec2(2.0, 1.0))));
    float shore_add = depth_fade + shore_sine;
    
    vec4 foam_noise = top_down_projection(_Shore_Foam_Noise_Texture, vec2(_Shore_Foam_Noise_Scale * 0.005), vec2(0.2), WorldNormal, AbsoluteWorldSpacePosition);
    float shore_foam_mult = clamp(shore_add * clamp(pow(foam_noise.r, 0.2), 0.0, 1.0), 0.0, 1.0);
    
    float w_thick = clamp(_Shore_Wave_Thickness, 0.0, 1.0);
    float w_remap1 = remap(shore_mod, vec2(0.0, 1.0), vec2(-w_thick, 1.0));
    float w_remap2 = remap(shore_mod, vec2(0.0, 1.0), vec2(3.0, -3.0));
    float w_sat1 = 1.0 - clamp(w_remap1, 0.0, 1.0);
    float w_sat2 = 1.0 - clamp(w_remap2, 0.0, 1.0);
    float w_mask = clamp((w_sat2 * w_sat2 * w_remap1) + w_sat1, 0.0, 1.0);
    
    float w_floor = floor(w_mask) - floor(clamp(w_mask + shore_foam_mult, 0.0, 1.0));
    float w_final = clamp(w_floor, 0.0, 1.0);
    vec4 shore_wave_final = _Enable_Shore_Wave_Foam ? (_Shore_Wave_Color_Tint * mix(vec4(0.0), vec4(w_final), _Shore_Edge_Opacity / 1.5)) : vec4(0.0);
    
    // -----------------------------------------
    // Shore Edge & Small Foam
    // -----------------------------------------
    float edge_div = clamp(pow(depth_fade / _Shore_Edge_Thickness, 2.0), 0.0, 1.0);
    vec4 shore_edge_final = _Enable_Shore_Foam ? (_Shore_Foam_Color_Tint * ((1.0 - edge_div) * _Shore_Edge_Opacity)) : vec4(0.0);
    
	vec4 sm_foam_tex = top_down_projection(_Noise_Texture, vec2(_Shore_Small_Foam_Tiling * 0.8), vec2(TIME * 0.0012), WorldNormal, AbsoluteWorldSpacePosition);
    float sm_foam_pow = clamp(pow(sm_foam_tex.r * 5.0, 20.0), 0.0, 1.0);
    float sm_foam_mask = 1.0 - clamp(depth_fade / 2.0, 0.0, 1.0);
    vec4 sm_foam_final = _Enable_Shore_Foam ? (_Shore_Foam_Color_Tint * mix(0.0, sm_foam_pow, _Shore_Small_Foam_Opacity / 3.0)) : vec4(0.0);
    
    // -----------------------------------------
    // Global Ocean Foam & Fresnel
    // -----------------------------------------
    vec4 g_foam_tex = top_down_projection(_Noise_Texture, vec2(4.025), vec2(0.0), WorldNormal, AbsoluteWorldSpacePosition);
    
    float wind_dot = clamp(dot(normalize(_WindDirection), vec3(0.0, 0.0, 1.0)), -1.0, 1.0);
	float wind_acos = degrees(acos(wind_dot));
	float wind_angle = (normalize(_WindDirection).x >= 0.0 ? (1.0 - wind_acos) : wind_acos) + 225.0;

	float ow_frac = fract((
	    rotate_about_axis(AbsoluteWorldSpacePosition, vec3(0.0, 1.0, 0.0), wind_angle).x + 
	    rotate_about_axis(AbsoluteWorldSpacePosition, vec3(0.0, 1.0, 0.0), wind_angle).z + 
	    ((_Ocean_Wave_Speed * 10.0) * TIME)
	) * 0.01);
                    
    vec4 ow_grad = sample_ocean_wave_gradient(ow_frac);
    float ow_pow = clamp(pow(ow_grad.r, remap(_Ocean_Foam_Amount, vec2(0.0, 1.0), vec2(5.0, 1.0))), 0.0, 1.0);
    float ow_mult = clamp(g_foam_tex.r * (ow_pow * _Ocean_Foam_Amount), 0.0, 1.0);
    
    vec4 br_tex = top_down_projection(_Noise_Texture, vec2(_Ocean_Foam_Breakup_Tiling * 0.001), vec2(TIME * -0.002, 0.0), WorldNormal, AbsoluteWorldSpacePosition);
    float ow_d_sat = clamp(depth_fade * 0.05, 0.0, 1.0);
    float br_pow = clamp(pow(clamp((ow_d_sat * (br_tex.r + 0.18)) * ow_d_sat, 0.0, 1.0) * 20.0, 20.0), 0.0, 1.0);
    
    float fresnel = pow(1.0 - clamp(dot(normalize(WorldNormal), ViewDir), 0.0, 1.0), _Fade_Power);
    float fresnel_smooth = smoothstep(0.0, 1.0, 1.0 - (_Fade_Distance * fresnel));
    float norm_int_fade = _Enable_Fresnel_Fade ? (fresnel_smooth * _Normal_Intensity) : _Normal_Intensity;
    vec4 g_foam_final = _Enable_Global_Foam ? vec4(br_pow * (_Ocean_Foam_Opacity * norm_int_fade)) : vec4(0.0);
    
    // -----------------------------------------
    // Distortion
    // -----------------------------------------
    vec2 dist_speed = remap(_Distortion_Speed, vec2(0.0, 1.0), vec2(0.0, 0.001)) * _Distortion_Direction * TIME;
    float dist_noise = unity_gradient_noise(UV + dist_speed, remap(_Distortion_Size, vec2(0.0, 1.0), vec2(0.0, 200.0)));
    vec2 dist_uv = SCREEN_UV + (dist_noise * remap(_Distortion_Strength, vec2(0.0, 1.0), vec2(0.0, 0.05)));
    vec3 scene_color = texture(screen_texture, dist_uv).rgb;
    vec3 base_distorted = _Enable_Distortion ? (color_very_deep.rgb + scene_color * 0.65) : color_very_deep.rgb;
    
    // -----------------------------------------
    // Normals (PBR Surface Mapping)
    // -----------------------------------------
    float n_remap = remap(_Normal_Tiling, vec2(0.0, 1.0), vec2(0.0, 0.04));
    vec2 n_speed1 = (_Normal_Pan_Speed * 0.02) * vec2(1.0, 1.0) * TIME;
    vec4 n_tex1 = top_down_projection_normal(_Normal_Texture, vec2(n_remap), n_speed1, WorldNormal, AbsoluteWorldSpacePosition);
    
    vec2 n_speed2 = n_speed1 * vec2(1.0, -1.0) * 0.2;
    vec4 n_tex2 = top_down_projection_normal(_Normal_Texture, vec2(n_remap * -1.1), n_speed2, WorldNormal, AbsoluteWorldSpacePosition);
    
    vec3 n_blended = normalize(vec3(n_tex1.xy + n_tex2.xy, n_tex1.z * n_tex2.z));
    vec3 normal_final = _Enable_Normals ? mix(vec3(0.0, 0.0, 1.0), n_blended, norm_int_fade) : vec3(0.0, 0.0, 1.0);
    
    // -----------------------------------------
    // Final Compositing & Alpha Output
    // -----------------------------------------
    float opacity_sat = clamp(depth_fade / 15.0, 0.0, 1.0);
    float alpha_remap = remap(opacity_sat, vec2(0.0, 1.0), vec2(_Shallows_Opacity, 1.0));
    float final_alpha = clamp(alpha_remap - (1.0 - _Base_Opacity), 0.0, 1.0);
    
    vec3 final_color = base_distorted 
                     + scroll_final.rgb 
                     + caustics_final.rgb 
                     + shore_edge_final.rgb 
                     + shore_wave_final.rgb 
                     + sm_foam_final.rgb 
                     + g_foam_final.rgb;

    ALBEDO = final_color;
    ALPHA = final_alpha;
    ROUGHNESS = 1.0 - _Smoothness;
    METALLIC = _Metallic;
    
    // Applying the calculated flat tangent-space normal projection back into Godot's NORMAL_MAP format (0 to 1)
    NORMAL_MAP = normal_final * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 1.0;
}