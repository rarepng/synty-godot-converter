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
render_mode blend_mix, depth_draw_always, diffuse_lambert, specular_schlick_ggx, cull_disabled;

// -------------------------------------------------------------------------
// BASE MATERIAL & DEPTH COLORS
// -------------------------------------------------------------------------
group_uniforms Base_Material_And_Depth;
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

// -------------------------------------------------------------------------
// SHORE WAVES & FOAM
// -------------------------------------------------------------------------
group_uniforms Shore_Waves_And_Foam;
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

// -------------------------------------------------------------------------
// OCEAN WAVES & FOAM
// -------------------------------------------------------------------------
group_uniforms Ocean_Waves_And_Foam;
uniform bool _Enable_Ocean_Wave = false;
uniform float _Ocean_Wave_Height : hint_range(0.0, 10.0) = 1.0;
uniform float _Ocean_Wave_Speed : hint_range(0.0, 1.0) = 0.5;
uniform float _Ocean_Foam_Amount : hint_range(0.0, 1.0) = 0.5;
uniform float _Ocean_Foam_Opacity : hint_range(0.0, 1.0) = 0.4;
uniform float _Ocean_Foam_Breakup_Tiling = 1.0;

// -------------------------------------------------------------------------
// CAUSTICS
// -------------------------------------------------------------------------
group_uniforms Caustics;
uniform bool _Enable_Caustics = true;
uniform float _Caustics_Scale = 15.0;
uniform bool _Caustics_Use_Voronoi_Noise = true;
uniform vec4 _Caustics_Color : source_color = vec4(0.7529412, 0.7333333, 0.6509804, 0.9);
uniform float _Caustics_Intensity : hint_range(0.0, 1.0) = 0.2;
uniform float _Caustics_Speed = 10.0;
uniform sampler2D _SampleTexture2D : hint_default_white, filter_linear_mipmap_anisotropic;
uniform float _Caustics_Fade_Depth = 20.0;

// -------------------------------------------------------------------------
// NORMALS
// -------------------------------------------------------------------------
group_uniforms Normals;
uniform bool _Enable_Normals = true;
uniform sampler2D _Normal_Texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec2 _Normal_Offset = vec2(0.0, 0.0);
uniform float _Normal_Tiling = 0.01;
uniform float _Normal_Intensity : hint_range(0.0, 1.0) = 1.0;
uniform float _Normal_Pan_Speed = 1.0;
uniform float _Normal_Noise_Tiling = 1.0;
uniform float _Normal_Noise_Intensity = 1.0;

// -------------------------------------------------------------------------
// TOP SCROLLING TEXTURE
// -------------------------------------------------------------------------
group_uniforms Top_Scrolling_Texture;
uniform bool _Enable_Top_Scrolling_Texture = true;
uniform vec2 _Scrolling_Texture_Direction = vec2(0.0, -0.5);
uniform sampler2D _Scrolling_Texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec2 _Scrolling_Texture_Tiling = vec2(1.0, 1.0);
uniform vec4 _Scrolling_Texture_Tint : source_color = vec4(0.3712175, 0.7245609, 0.8113208, 0.8);
uniform float _Scrolling_Texture_Opacity : hint_range(0.0, 1.0) = 0.2;

// -------------------------------------------------------------------------
// DISTORTION
// -------------------------------------------------------------------------
group_uniforms Distortion;
uniform bool _Enable_Distortion = false;
uniform float _Distortion_Speed = 0.2;
uniform vec2 _Distortion_Direction = vec2(0.1, 0.1);
uniform float _Distortion_Strength = 0.06;
uniform float _Distortion_Size = 10.0;

// -------------------------------------------------------------------------
// FRESNEL FADE
// -------------------------------------------------------------------------
group_uniforms Fresnel_Fade;
uniform bool _Enable_Fresnel_Fade = true;
uniform float _Fade_Distance = 1.0;
uniform float _Fade_Power : hint_range(0.0, 10.0) = 5.0;
// -------------------------------------------------------------------------
// GLOBAL FOAM & NOISE
// -------------------------------------------------------------------------
group_uniforms Global_Foam_And_Noise;
uniform bool _Enable_Global_Foam = false;
uniform sampler2D _Noise_Texture : hint_default_white, filter_linear_mipmap_anisotropic;

// -------------------------------------------------------------------------
// SYSTEM & EXTERNAL VARIABLES
// -------------------------------------------------------------------------
group_uniforms System_Variables;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec3 _WindDirection = vec3(1.0, 0.0, 1.0);
uniform float _GaleStrength = 1.0;

group_uniforms;

// -------------------------------------------------------------------------
// VARYINGS
// -------------------------------------------------------------------------
varying vec3 var_AbsoluteWorldSpacePosition;
varying vec3 var_WorldNormal;

// ============================================================================
// HASH & NOISE UTILITIES
// ============================================================================

vec2 hash_tchou_2_2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

float hash_tchou_2_1(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 unity_voronoi_random_vector_deterministic(vec2 uv_in, float offset) {
    vec2 hash = hash_tchou_2_2(uv_in);
    return vec2(sin(hash.y * offset), cos(hash.x * offset)) * 0.5 + 0.5;
}

vec2 unity_gradient_noise_deterministic_dir(vec2 p) {
    float x = hash_tchou_2_1(p);
    return normalize(vec2(x - floor(x + 0.5), abs(x) - 0.5));
}

vec4 sample_ocean_wave_gradient(float t) {
    t = clamp(t, 0.0, 1.0);
    
    vec4 c0 = vec4(0.0, 0.0, 0.0, 0.0);
    vec4 c1 = vec4(1.0, 1.0, 1.0, 0.5000076);
    vec4 c2 = vec4(0.0, 0.0, 0.0, 1.0);
    
    vec3 color;
    if (t <= c1.a) {
        color = mix(c0.rgb, c1.rgb, (t - c0.a) / (c1.a - c0.a));
    } else {
        color = mix(c1.rgb, c2.rgb, (t - c1.a) / (c2.a - c1.a));
    }
    
    return vec4(color, 1.0);
}


// ============================================================================
// CUSTOM UNITY RECREATIONS
// ============================================================================

vec2 unity_flipbook_invert_y(vec2 uv_in, float width, float height, float progress, vec2 invert) {
    progress = mod(progress, width * height);
    vec2 tile_count = 1.0 / vec2(width, height);
    
    float tile_y = abs(invert.y * height - (floor(progress * tile_count.x) + invert.y));
    float tile_x = abs(invert.x * width - (progress - width * floor(progress * tile_count.x) + invert.x));
    
    return (uv_in + vec2(tile_x, tile_y)) * tile_count;
}

vec2 unity_voronoi_deterministic(vec2 uv_in, float angle_offset, float cell_density) {
    vec2 g = floor(uv_in * cell_density);
    vec2 f = fract(uv_in * cell_density);
    vec3 res = vec3(8.0, 0.0, 0.0);
    
    for(int y = -1; y <= 1; y++) {
        for(int x = -1; x <= 1; x++) {
            vec2 lattice = vec2(float(x), float(y));
            vec2 offset = unity_voronoi_random_vector_deterministic(lattice + g, angle_offset);
            float d = distance(lattice + offset, f);
            
            if(d < res.x) {
                res = vec3(d, offset.x, offset.y);
            }
        }
    }
    return res.xy;
}

float unity_gradient_noise_deterministic(vec2 p, float scale) {
    p *= scale;
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    
    float d00 = dot(unity_gradient_noise_deterministic_dir(ip), fp);
    float d10 = dot(unity_gradient_noise_deterministic_dir(ip + vec2(1.0, 0.0)), fp - vec2(1.0, 0.0));
    float d01 = dot(unity_gradient_noise_deterministic_dir(ip + vec2(0.0, 1.0)), fp - vec2(0.0, 1.0));
    float d11 = dot(unity_gradient_noise_deterministic_dir(ip + vec2(1.0, 1.0)), fp - vec2(1.0, 1.0));
    
    vec2 blend = fp * fp * fp * (fp * (fp * 6.0 - 15.0) + 10.0);
    return mix(mix(d00, d10, blend.x), mix(d01, d11, blend.x), blend.y) + 0.5;
}

vec3 unity_normal_blend(vec3 a, vec3 b) {
    return normalize(vec3(a.xy + b.xy, a.z * b.z));
}
// --- CORE SHADER GRAPH FUNCTIONS ---

void SG_OceanWaveMask(float _OceanWaveSpeed, float _OceanWaveHeight, vec3 _WindDirection_in, float _GaleStrength_in, vec3 world_pos_in, float time_in, out vec3 Position_1, out float ZOffset_2) {
    float gale_clamped = clamp(_GaleStrength_in, 0.0, 1.0);
    float add_gale = gale_clamped + 1.5;
    
    vec3 wind_dir = normalize(_WindDirection_in);
    float rad_to_deg = degrees(acos(dot(wind_dir, vec3(0.0, 0.0, 1.0))));
    float final_angle_rad = radians((wind_dir.x >= 0.0 ? (1.0 - rad_to_deg) : rad_to_deg) + 225.0);
    
    float s = sin(final_angle_rad);
    float c = cos(final_angle_rad);
    vec3 rotated_pos = vec3(
        world_pos_in.x * c + world_pos_in.z * s,
        world_pos_in.y,
        -world_pos_in.x * s + world_pos_in.z * c
    );
    
    float frac_val = fract(((_OceanWaveSpeed * add_gale * 10.0 * time_in) + (rotated_pos.x + rotated_pos.z)) * 0.01);
    vec4 grad_sample = sample_ocean_wave_gradient(frac_val);
    
    float rg_sum = grad_sample.r + grad_sample.g;
    
    Position_1 = vec3(grad_sample.r, rg_sum * (rg_sum * _OceanWaveHeight), -grad_sample.b);
    ZOffset_2 = grad_sample.r;
}

void SG_DepthFade(sampler2D depth_texture_in, vec2 screen_uv_in, vec4 fragcoord_in, mat4 inv_proj_matrix_in, out vec4 OutVector4_1) {
    vec3 ndc = vec3(screen_uv_in * 2.0 - 1.0, texture(depth_texture_in, screen_uv_in).x);
    vec4 view = inv_proj_matrix_in * vec4(ndc, 1.0);
    float linear_eye_depth = -(view.z / view.w); 
    
    vec3 frag_ndc = vec3(screen_uv_in * 2.0 - 1.0, fragcoord_in.z);
    vec4 frag_view = inv_proj_matrix_in * vec4(frag_ndc, 1.0);
    float frag_linear_depth = -(frag_view.z / frag_view.w);
    
    OutVector4_1 = vec4(linear_eye_depth - frag_linear_depth);
}

void SG_TopDownProjection(sampler2D _Texture, vec2 _Tiling, vec2 _Offset, out vec4 OutVector4_1, out float R_2, out float G_3, out float B_4, out float A_5) {
    vec2 final_uv = (vec2(sign(var_WorldNormal.y), 1.0) * vec2(var_AbsoluteWorldSpacePosition.x, -var_AbsoluteWorldSpacePosition.z) * _Tiling) + _Offset;
    
    OutVector4_1 = texture(_Texture, final_uv);
    R_2 = OutVector4_1.r;
    G_3 = OutVector4_1.g;
    B_4 = OutVector4_1.b;
    A_5 = OutVector4_1.a;
}

void SG_Panner(vec2 _UV, vec2 _Speed, float time, out vec2 Out_Vector4_1) {
    Out_Vector4_1 = _UV + (_Speed * time);
}

void SG_TopDownProjectionNormal(sampler2D _Texture, vec2 _Tiling, vec2 _Offset, out vec4 OutVector4_1, out float R_2, out float G_3, out float B_4) {
    vec2 final_uv = (vec2(sign(var_WorldNormal.y), 1.0) * vec2(var_AbsoluteWorldSpacePosition.x, -var_AbsoluteWorldSpacePosition.z) * _Tiling) + _Offset;
    
    vec4 samp = texture(_Texture, final_uv);
    samp.rgb = samp.rgb * 2.0 - 1.0;
    
    OutVector4_1 = samp;
    R_2 = samp.r;
    G_3 = samp.g;
    B_4 = samp.b;
}

// --- VERTEX FUNCTION ---

void vertex() {
    vec3 in_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    vec3 wave_pos_out;
    float wave_z_offset_out;
    
    SG_OceanWaveMask(
        _Ocean_Wave_Speed, 
        _Ocean_Wave_Height, 
        _WindDirection, 
        _GaleStrength, 
        in_world_pos, 
        TIME, 
        wave_pos_out, 
        wave_z_offset_out
    );
    
    vec3 subtract_vec = wave_pos_out - vec3(0.0, _Ocean_Wave_Height / 2.0, 0.0);
    
    VERTEX = _Enable_Ocean_Wave ? (VERTEX + subtract_vec) : VERTEX;
    
    var_AbsoluteWorldSpacePosition = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    var_WorldNormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    // --- RECONSTRUCTIONS (DEPTH & WORLD SPACE) ---
	vec4 depth_fade_vec;
    SG_DepthFade(depth_texture, SCREEN_UV, FRAGCOORD, INV_PROJECTION_MATRIX, depth_fade_vec);
    float raw_depth_fade = depth_fade_vec.x;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, texture(depth_texture, SCREEN_UV).x);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    vec3 frag_ndc = vec3(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z);
    vec4 frag_view = INV_PROJECTION_MATRIX * vec4(frag_ndc, 1.0);
    frag_view.xyz /= frag_view.w;
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - var_AbsoluteWorldSpacePosition);
    vec3 bg_world_pos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
	
	// --- TOP SCROLLING TEXTURE ---
    vec2 world_xz = vec2(var_AbsoluteWorldSpacePosition.x, -var_AbsoluteWorldSpacePosition.z);
    vec2 top_scroll_uv = (world_xz * _Scrolling_Texture_Tiling) + (_Scrolling_Texture_Direction * TIME);
    vec4 top_scroll_tex = texture(_Scrolling_Texture, top_scroll_uv);
    float top_scroll_mask = top_scroll_tex.r * _Scrolling_Texture_Opacity * _Scrolling_Texture_Tint.a;
	
    // --- BASE WATER COLORS ---
	// too harsh
    //vec4 saturate_deep = clamp(depth_fade_vec / vec4(abs(_Deep_Height)), 0.0, 1.0);
    //vec4 grad_deep = vec4(mix(vec3(1.0), vec3(0.0), saturate_deep.x), 1.0);
    //vec4 lerp_deep = mix(_Deep_Color, _Shallow_Color, grad_deep);
    //vec4 saturate_very_deep = clamp(depth_fade_vec / vec4(abs(_Very_Deep_Height)), 0.0, 1.0);
    //vec3 grad_very_deep_col = saturate_very_deep.x < 0.5000076 ? mix(vec3(0.0), vec3(1.0), saturate_very_deep.x / 0.5000076) : vec3(1.0);
    //vec4 base_water_color = mix(lerp_deep, _Very_Deep_Color, vec4(grad_very_deep_col, 1.0));
	
	// --- BASE WATER COLORS ---
    float deep_blend = smoothstep(0.0, _Deep_Height, raw_depth_fade);
    float very_deep_blend = smoothstep(0.0, _Very_Deep_Height, raw_depth_fade);
    vec4 shallow_to_deep = mix(_Shallow_Color, _Deep_Color, deep_blend);
    vec4 base_water_color = mix(shallow_to_deep, _Very_Deep_Color, very_deep_blend);

    // --- CAUSTICS (VORONOI & FLIPBOOK) ---
    vec2 caustics_vec = vec2(bg_world_pos.x, bg_world_pos.z);
    float voronoi_val = unity_voronoi_deterministic(caustics_vec, (TIME + 100.0) * 2.0, 3.0).x;
    float voronoi_saturate = clamp(pow(voronoi_val, 4.0), 0.0, 1.0);
    vec2 caustics_fract = fract(caustics_vec / vec2(max(_Caustics_Scale, 0.01)));
    float caustics_floor = floor(TIME * (_Caustics_Speed * 10.0));
    float flipbook_val = texture(_SampleTexture2D, unity_flipbook_invert_y(caustics_fract, 8.0, 8.0, caustics_floor, vec2(0.0, 1.0))).r;

    float caustics_branch = _Caustics_Use_Voronoi_Noise ? voronoi_saturate : flipbook_val;
    vec4 caustics_depth_sat = clamp(depth_fade_vec * vec4(1.0 / _Caustics_Fade_Depth), 0.0, 1.0);
    vec4 caustics_mask = (vec4(1.0) - caustics_depth_sat) * caustics_depth_sat;
    vec4 caustics_color_base = _Caustics_Color * (vec4(caustics_branch) * caustics_mask);

    float depth_mask = 1.0 - (clamp(raw_depth_fade, 0.0, _Caustics_Fade_Depth) / _Caustics_Fade_Depth);
    vec4 caustics_final = clamp(caustics_color_base * vec4((_Caustics_Intensity * 4.0) * depth_mask), 0.0, 1.0);
    vec4 caustics_result = _Enable_Caustics ? caustics_final : vec4(0.0);

    // --- SHORE WAVES & FOAM ---
    float shore_time = _Enable_Shore_Animation ? TIME : _Animation_Offset;
    float shore_wave_time = shore_time * _Shore_Wave_Speed;

    vec4 proj_noise1; float pr1, pg1, pb1, pa1;
	SG_TopDownProjection(_Noise_Texture, vec2(_Shore_Edge_Noise_Scale * 0.005), vec2(0.0), proj_noise1, pr1, pg1, pb1, pa1);

    float raw_time = shore_wave_time + clamp(pr1, 0.0, 1.0);
    float max_point = 0.75;
    float cycle_duration = max_point * 2.0;
    float cycle = mod(raw_time, cycle_duration);
    float shore_mod = cycle < max_point ? cycle : cycle_duration - cycle;
    float shore_sine = sin(shore_mod * (PI / (2.0 + _Shore_Wave_Return_Amount * -1.0)));
    float shore_add = raw_depth_fade + shore_sine;

    vec4 proj_noise2; float pr2, pg2, pb2, pa2;
    SG_TopDownProjection(_Shore_Foam_Noise_Texture, vec2(_Shore_Foam_Noise_Scale * 0.005), vec2(0.0), proj_noise2, pr2, pg2, pb2, pa2);
    
    float shore_wave_base = clamp(shore_add * clamp(pow(pr2, 0.2), 0.0, 1.0), 0.0, 1.0);
    float shore_thickness_val = clamp(_Shore_Wave_Thickness, 0.0, 1.0) * 0.99;
    float one_minus_mod2 = 1.0 - clamp(3.0 + shore_mod * -6.0, 0.0, 1.0);
    float shore_foam_val = shore_wave_base + (shore_thickness_val * (one_minus_mod2 * one_minus_mod2));

    float shore_edge_fract = clamp(floor(shore_foam_val) - floor(shore_wave_base), 0.0, 1.0);
    vec4 shore_edge_tint = _Shore_Wave_Color_Tint * vec4(mix(0.0, shore_edge_fract, _Shore_Edge_Opacity / 1.5));
    vec4 shore_wave_pass1 = _Enable_Shore_Wave_Foam ? shore_edge_tint : vec4(0.0);
    vec4 shore_wave_combined = shore_wave_pass1 + shore_wave_pass1;

    vec4 depth_edge_sat = clamp(pow(depth_fade_vec / vec4(_Shore_Edge_Thickness), vec4(2.0)), 0.0, 1.0);
    vec4 edge_foam_tint = _Shore_Wave_Color_Tint * ((vec4(1.0) - depth_edge_sat) * vec4(_Shore_Edge_Opacity));
    vec4 shore_wave_total = shore_wave_combined + (_Enable_Shore_Wave_Foam ? edge_foam_tint : vec4(0.0));

    vec4 depth_small_sat = clamp(depth_fade_vec / vec4(2.0), 0.0, 1.0);
    vec4 small_foam_mask = (vec4(1.0) - depth_small_sat) * vec4(0.8);

    vec4 proj_noise3; float pr3, pg3, pb3, pa3;
    SG_TopDownProjection(_Noise_Texture, vec2(_Shore_Small_Foam_Tiling * 0.01), vec2(TIME * 0.003), proj_noise3, pr3, pg3, pb3, pa3);

    float small_foam_val = clamp(pow((small_foam_mask * vec4(pr3)).x * 5.0, 20.0), 0.0, 1.0);
    vec4 small_foam_tint = _Shore_Foam_Color_Tint * vec4(mix(0.0, small_foam_val, _Shore_Small_Foam_Opacity / 3.0));
    vec4 shore_total = shore_wave_total + (_Enable_Shore_Foam ? small_foam_tint : vec4(0.0));

    // --- OCEAN WAVES & FOAM ---
    vec2 foam_offset1 = vec2(TIME * 0.0031, TIME * 0.0017); 
    
    vec4 proj_noise4; float pr4, pg4, pb4, pa4;
    SG_TopDownProjection(_Noise_Texture, vec2(0.007), foam_offset1, proj_noise4, pr4, pg4, pb4, pa4);
    
    vec3 ocean_pos; float ocean_z;
    SG_OceanWaveMask(_Ocean_Wave_Speed, _Ocean_Wave_Height, _WindDirection, _GaleStrength, var_AbsoluteWorldSpacePosition, TIME, ocean_pos, ocean_z);
    
    vec2 foam_offset2 = vec2(TIME * -0.0023, TIME * 0.0041) + vec2(pr4 * 0.05);

    vec4 proj_noise5; float pr5, pg5, pb5, pa5;
    SG_TopDownProjection(_Noise_Texture, vec2(_Ocean_Foam_Breakup_Tiling * 0.025), foam_offset2, proj_noise5, pr5, pg5, pb5, pa5);
    float organic_noise = smoothstep(-0.3, 1.0, pr4 - (pr5 * 0.5)); 

    float distorted_crest = clamp(ocean_z + (pr4 - 0.5) * 0.6, 0.0, 1.0);
    float dist_from_crest = 1.0 - distorted_crest;
    float wave_suppression = (1.0 - pr4) * 1.5; 

    float penalty_factor = mix(5.0, 1.0, clamp(_Ocean_Foam_Amount, 0.0, 1.0));
    float penalty = (dist_from_crest * penalty_factor) + wave_suppression;
    float foam_signal = organic_noise - penalty;
    float base_mask = smoothstep(-0.2, 1.0, foam_signal);
    float ocean_foam_val = base_mask * base_mask;

    vec3 normalized_world_normal = normalize(var_WorldNormal);
    float fresnel = pow(1.0 - clamp(dot(normalized_world_normal, view_dir), 0.0, 1.0), max(_Fade_Power, 0.0001));
    float fresnel_intensity = smoothstep(0.0, 1.0, 1.0 - (_Fade_Distance * fresnel)) * _Normal_Intensity;
    float fade_branch = _Enable_Fresnel_Fade ? fresnel_intensity : _Normal_Intensity;
    
    vec4 global_foam_total = _Enable_Global_Foam ? vec4(ocean_foam_val * _Ocean_Foam_Opacity) : vec4(0.0);
    vec4 all_foams = (shore_total + global_foam_total) * _Foam_Color;
    float foam_alpha_intensity = clamp(max(max(all_foams.r, all_foams.g), all_foams.b), 0.0, 1.0);
    vec4 water_base_final = caustics_result + (base_water_color * (1.0 - foam_alpha_intensity) + all_foams);
    vec4 water_with_top = _Enable_Top_Scrolling_Texture ? mix(water_base_final, _Scrolling_Texture_Tint, clamp(top_scroll_mask, 0.0, 1.0)) : water_base_final;
	
    // --- SCREEN DISTORTION ---
    vec2 dist_uv = UV + (vec2(TIME * _Distortion_Speed * 0.001) * _Distortion_Direction);
    float dist_noise = unity_gradient_noise_deterministic(dist_uv, _Distortion_Size * 200.0);
    vec2 dist_screen_uv = SCREEN_UV + vec2(dist_noise * (_Distortion_Strength * 0.05));

    vec3 scene_col = texture(screen_texture, dist_screen_uv).rgb * 0.65;
    vec3 final_albedo = _Enable_Distortion ? (water_with_top.xyz + scene_col) : water_with_top.xyz;

    // --- NORMALS PROCESSING ---
    float norm_noise_tile = _Normal_Noise_Tiling * 0.01;
    vec4 proj_norm_noise1; float pnr1, png1, pnb1, pna1;
    SG_TopDownProjection(_Noise_Texture, vec2(norm_noise_tile), vec2(0.0), proj_norm_noise1, pnr1, png1, pnb1, pna1);

    vec2 norm_noise_offset2 = vec2((norm_noise_tile * 0.5) * -1.1, 0.0) * vec2(6.0, 6.0);
    vec4 proj_norm_noise2; float pnr2, png2, pnb2, pna2;
    SG_TopDownProjection(_Noise_Texture, vec2(norm_noise_tile), norm_noise_offset2, proj_norm_noise2, pnr2, png2, pnb2, pna2);

    vec2 panner_uv;
    SG_Panner(vec2(0.0), vec2(_Normal_Pan_Speed * 0.02), TIME, panner_uv);
    vec2 final_norm_uv = _Normal_Offset + vec2((pnr1 * pnr2) * _Normal_Noise_Intensity) + panner_uv;

    float norm_tile = _Normal_Tiling * 0.04;
    vec4 norm1; float n1r, n1g, n1b;
    SG_TopDownProjectionNormal(_Normal_Texture, vec2(norm_tile), final_norm_uv, norm1, n1r, n1g, n1b);

    vec4 norm2; float n2r, n2g, n2b;
    SG_TopDownProjectionNormal(_Normal_Texture, vec2(norm_tile * 0.2), final_norm_uv * vec2(1.0, -1.0), norm2, n2r, n2g, n2b);
	vec3 blended_norm = unity_normal_blend(norm1.xyz, norm2.xyz);
    vec3 faded_norm = mix(vec3(0.0, 0.0, 1.0), blended_norm, vec3(fade_branch));
    
    vec3 packed_norm = faded_norm * 0.5 + 0.5; 
    vec3 final_normal = _Enable_Normals ? packed_norm : vec3(0.5019608, 0.5019608, 1.0);

    // --- OPACITY RESOLUTION & FINAL OUTPUT ---
    vec4 opacity_sat = clamp(depth_fade_vec / vec4(15.0), 0.0, 1.0);
    vec4 opacity_remap = vec4(_Shallows_Opacity) + (opacity_sat * vec4(1.0 - _Shallows_Opacity));
    
    //float foam_alpha_intensity = max(max(all_foams.r, all_foams.g), all_foams.b);
    float final_alpha = clamp((foam_alpha_intensity + opacity_remap.x) - (1.0 - _Base_Opacity), 0.0, 1.0);

    ALBEDO = final_albedo;
    NORMAL_MAP = final_normal;
    EMISSION = vec3(0.0);
    METALLIC = _Metallic;
    SPECULAR = 0.5;
    ROUGHNESS = 1.0 - _Smoothness;
    ALPHA = final_alpha;
    ALPHA_SCISSOR_THRESHOLD = 0.5;
}