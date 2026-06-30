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
render_mode blend_mix, specular_schlick_ggx, cull_disabled; //  no depth_draw_opaque or cull_back but idk about diffuse_lambert, specular_disabled;

uniform float _Base_Opacity : hint_range(0.0, 1.0) = 0.941;
uniform float _Shallows_Opacity : hint_range(0.0, 1.0) = 0.616;

uniform vec4 _Shallow_Color : source_color = vec4(0.332, 0.723, 0.792, 1.0);
uniform vec4 _Deep_Color : source_color = vec4(0.209, 0.509, 0.497, 1.0);
uniform vec4 _Very_Deep_Color : source_color = vec4(0.098, 0.301, 0.367, 1.0);

uniform float _Deep_Height = 4.1;
uniform float _Very_Deep_Height = 31.38;

uniform float _Smoothness : hint_range(0.0, 1.0) = 0.776;
uniform float _Metallic : hint_range(0.0, 1.0) = 0.0;

uniform float _Enable_Ocean_Wave = 1.0;
uniform float _Ocean_Wave_Height : hint_range(0.0, 10.0) = 3.43;
uniform float _Ocean_Wave_Speed : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D _OceanWaveGradient : source_color, filter_linear, repeat_enable;

uniform float _Enable_Shore_Wave_Foam = 1.0;
uniform float _Enable_Shore_Animation = 1.0;
uniform float _Animation_Offset = 0.0;
uniform float _Shore_Edge_Opacity : hint_range(0.0, 1.0) = 0.369;
uniform float _Shore_Edge_Thickness : hint_range(0.0, 1.0) = 0.031;
uniform float _Shore_Edge_Noise_Scale = 0.4;
uniform float _Shore_Wave_Speed : hint_range(0.0, 1.0) = 0.318;
uniform float _Shore_Wave_Return_Amount : hint_range(0.0, 1.0) = 0.605;
uniform float _Shore_Wave_Thickness : hint_range(0.0, 1.0) = 0.323;
uniform vec4 _Shore_Wave_Color_Tint : source_color = vec4(0.528, 0.752, 0.867, 1.0);

uniform float _Enable_Shore_Foam = 1.0;
uniform float _Shore_Small_Foam_Opacity : hint_range(0.0, 1.0) = 0.339;
uniform float _Shore_Small_Foam_Tiling = 2.5;
uniform float _Shore_Foam_Noise_Scale = 2.0;
uniform vec4 _Shore_Foam_Color_Tint : source_color = vec4(0.529, 0.752, 0.866, 1.0);

uniform float _Enable_Caustics = 1.0;
uniform float _Caustics_Scale = 18.46;
uniform float _Caustics_Speed = 1.0;
uniform float _Caustics_Intensity : hint_range(0.0, 1.0) = 0.077;
uniform float _Caustics_Use_Voronoi_Noise = 0.0;
uniform vec4 _Caustics_Color : source_color = vec4(0.369, 0.99, 0.99, 1.0);

uniform float _Enable_Normals = 1.0;
uniform float _Normal_Intensity : hint_range(0.0, 1.0) = 1.0;
uniform float _Normal_Tiling = 2.0;
uniform float _Normal_Pan_Speed = 1.0;
uniform float _Normal_Noise_Intensity = 0.23;
uniform float _Normal_Noise_Tiling = 1.0;
uniform vec4 _Normal_Offset = vec4(0.0, 0.0, 0.0, 0.0);

uniform float _Enable_Global_Foam = 0.0;
uniform float _Ocean_Foam_Amount : hint_range(0.0, 1.0) = 0.0;
uniform float _Ocean_Foam_Opacity : hint_range(0.0, 1.0) = 0.0;
uniform float _Ocean_Foam_Breakup_Tiling = 1.0;

uniform float _Enable_Distortion = 0.0;
uniform float _Distortion_Speed = 0.2;
uniform vec4 _Distortion_Direction = vec4(0.1, 0.1, 0.0, 0.0);
uniform float _Distortion_Strength = 0.06;
uniform float _Distortion_Size = 10.0;

uniform float _Enable_Top_Scrolling_Texture = 0.0;
uniform vec4 _Scrolling_Texture_Direction = vec4(0.0, -0.01, 0.0, 0.0);
uniform vec4 _Scrolling_Texture_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 _Scrolling_Texture_Tint : source_color = vec4(0.371, 0.724, 0.811, 0.0);
uniform float _Scrolling_Texture_Opacity : hint_range(0.0, 1.0) = 1.0;

uniform float _Enable_Fresnel_Fade = 0.0;
uniform float _Fade_Distance = 1.0;
uniform float _Fade_Power = 0.0;

uniform sampler2D _Normal_Texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D _Noise_Texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D _Shore_Foam_Noise_Texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D _Scrolling_Texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D _SampleTexture2D_c5bda943a6134644bb954c2c5ced7db4_Texture_1_Texture2D : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform float _AlphaClip = 0.0;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// copied from HLSL EXACTLY
float Hash_Tchou_2_1(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}
vec2 Hash_Tchou_2_2(vec2 uv) {
    uv = vec2(dot(uv, vec2(127.1, 311.7)), dot(uv, vec2(269.5, 183.3)));
    return fract(sin(uv) * 43758.5453123);
}
vec3 Unity_Rotate_About_Axis_Degrees(vec3 In, vec3 Axis, float Rotation) {
    float rot = radians(Rotation);
    float s = sin(rot);
    float c = cos(rot);
    Axis = normalize(Axis);
    return In * c + cross(Axis, In) * s + Axis * dot(Axis, In) * (1.0 - c);
}
vec2 Unity_TilingAndOffset(vec2 uv_val, vec2 Tiling, vec2 Offset) {
    return uv_val * Tiling + Offset;
}
float Unity_Remap(float In, vec2 InMinMax, vec2 OutMinMax) {
    return OutMinMax.x + (In - InMinMax.x) * (OutMinMax.y - OutMinMax.x) / (InMinMax.y - InMinMax.x);
}
float Unity_FresnelEffect(vec3 Normal, vec3 ViewDir, float Power) {
    return pow((1.0 - clamp(dot(normalize(Normal), ViewDir), 0.0, 1.0)), Power);
}
vec3 Unity_NormalBlend(vec3 A, vec3 B) {
    return normalize(vec3(A.rg + B.rg, A.b * B.b));
}
vec2 Unity_Flipbook_InvertY(vec2 uv_val, float Width, float Height, float Tile, vec2 Invert) {
    Tile = floor(mod(Tile + 0.00001, Width * Height));
    vec2 tileCount = vec2(1.0, 1.0) / vec2(Width, Height);
    float base = floor((Tile + 0.5) * tileCount.x);
    float tileX = (Tile - Width * base);
    float tileY = (Invert.y * Height - (base + Invert.y * 1.0));
    return (uv_val + vec2(tileX, tileY)) * tileCount;
}
vec2 Unity_Voronoi_RandomVector_Deterministic(vec2 uv_val, float offset) {
    vec2 hash = Hash_Tchou_2_2(uv_val);
    return vec2(sin(hash.y * offset), cos(hash.x * offset)) * 0.5 + 0.5;
}
void Unity_Voronoi_Deterministic(vec2 uv_val, float AngleOffset, float CellDensity, out float Out, out float Cells) {
    vec2 g = floor(uv_val * CellDensity);
    vec2 f = fract(uv_val * CellDensity);
    vec3 res = vec3(8.0, 0.0, 0.0);
    
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 lattice = vec2(float(x), float(y));
            vec2 offset = Unity_Voronoi_RandomVector_Deterministic(lattice + g, AngleOffset);
            float d = distance(lattice + offset, f);
            if (d < res.x) {
                res = vec3(d, offset.x, offset.y);
                Out = res.x;
                Cells = res.y;
            }
        }
    }
}
vec2 Unity_GradientNoise_Deterministic_Dir(vec2 p) {
    float x = Hash_Tchou_2_1(p);
    return normalize(vec2(x - floor(x + 0.5), abs(x) - 0.5));
}
float Unity_GradientNoise_Deterministic(vec2 uv_val, vec3 Scale) {
    vec2 p = uv_val * Scale.xy;
    vec2 ip = floor(p);
    vec2 fp = fract(p);
    float d00 = dot(Unity_GradientNoise_Deterministic_Dir(ip), fp);
    float d01 = dot(Unity_GradientNoise_Deterministic_Dir(ip + vec2(0.0, 1.0)), fp - vec2(0.0, 1.0));
    float d10 = dot(Unity_GradientNoise_Deterministic_Dir(ip + vec2(1.0, 0.0)), fp - vec2(1.0, 0.0));
    float d11 = dot(Unity_GradientNoise_Deterministic_Dir(ip + vec2(1.0, 1.0)), fp - vec2(1.0, 1.0));
    fp = fp * fp * fp * (fp * (fp * 6.0 - 15.0) + 10.0);
    return mix(mix(d00, d01, fp.y), mix(d10, d11, fp.y), fp.x) + 0.5;
}

vec2 SG_Panner(vec2 uv_val, vec2 Speed, vec3 TimeParameters) {
    return uv_val + (Speed * vec2(TimeParameters.x, TimeParameters.x));
}

void SG_OceanWaveMask(float OceanWaveSpeed, sampler2D OceanWaveGradient, float OceanWaveHeight, vec3 WindDirection, float GaleStrength, vec3 AbsoluteWorldSpacePosition, vec3 TimeParameters, out float final_y_displacement, out float ZOffset) {
    float time_speed = OceanWaveSpeed * 10.0 * TimeParameters.x;
    vec3 norm_wind = normalize(WindDirection);
    bool comp = norm_wind.x >= 0.0;
    
    float dot_prod = dot(norm_wind, vec3(0.0, 0.0, 1.0));
    
    float angle_deg = degrees(acos(clamp(dot_prod, -1.0, 1.0)));
    float inverse_angle = 1.0 - angle_deg;
    
    float branch_val = comp ? inverse_angle : angle_deg;
    float rotation_val = branch_val + 225.0;
    
    vec3 rotated_pos = Unity_Rotate_About_Axis_Degrees(AbsoluteWorldSpacePosition, vec3(0.0, 1.0, 0.0), rotation_val);
    
    float pos_r_b = rotated_pos.x + rotated_pos.z;
    float time_pos_sum = time_speed + pos_r_b;
    float gradient_uv = fract(time_pos_sum * 0.01);
    
    vec4 gradient_sample = texture(OceanWaveGradient, vec2(gradient_uv, 0.0));
    
    float height_val = gradient_sample.r + gradient_sample.g;
    final_y_displacement = height_val * (height_val * OceanWaveHeight); 
    ZOffset = gradient_sample.r;
}

void SG_TopDownProjection(sampler2D Texture, vec2 Tiling, vec2 Offset, vec3 WorldSpaceNormal, vec3 AbsoluteWorldSpacePosition, out vec4 OutVector4, out float R, out float G, out float B, out float A) {
    vec3 sign_norm = sign(WorldSpaceNormal) * vec3(-1.0, 1.0, 1.0);
    vec2 rg_val = vec2(sign_norm.y, 1.0);
    
    vec3 pos_mult = AbsoluteWorldSpacePosition * vec3(1.0);
    vec3 inverted_z = pos_mult * vec3(1.0, 1.0, -1.0);
    
    vec2 proj_uv = rg_val * vec2(inverted_z.x, inverted_z.z);
    vec2 final_uv = Unity_TilingAndOffset(proj_uv, Tiling, Offset);
    
    OutVector4 = texture(Texture, final_uv);
    R = OutVector4.r;
    G = OutVector4.g;
    B = OutVector4.b;
    A = OutVector4.a;
}

void SG_TopDownProjectionNormal(sampler2D Texture, vec2 Tiling, vec2 Offset, vec3 WorldSpaceNormal, vec3 AbsoluteWorldSpacePosition, out vec4 OutVector4, out float R, out float G, out float B) {
    vec3 sign_norm = sign(WorldSpaceNormal) * vec3(-1.0, 1.0, 1.0);
    vec2 rg_val = vec2(sign_norm.y, 1.0);
    
    vec3 pos_mult = AbsoluteWorldSpacePosition * vec3(1.0);
    vec3 inverted_z = pos_mult * vec3(1.0, 1.0, -1.0);
    
    vec2 proj_uv = rg_val * vec2(inverted_z.x, inverted_z.z);
    vec2 final_uv = Unity_TilingAndOffset(proj_uv, Tiling, Offset);
    
    vec4 normal_sample = texture(Texture, final_uv);
    
    OutVector4 = normal_sample;
    R = normal_sample.r;
    G = normal_sample.g;
    B = normal_sample.b;
}

// ==========================================
// VERTEX PASS
// ==========================================
void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 time_params = vec3(TIME, 0.0, 0.0);
    
    float wave_y;
    float wave_z_offset;
    SG_OceanWaveMask(
        _Ocean_Wave_Speed, 
        _OceanWaveGradient, 
        _Ocean_Wave_Height, 
        vec3(1.0, 0.0, 1.0), 
        1.0, 
        world_pos, 
        time_params, 
        wave_y, 
        wave_z_offset
    );
    
if (_Enable_Ocean_Wave > 0.5) {
    vec3 world_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    
    world_v.y += wave_y - (_Ocean_Wave_Height * 0.5);
    
    VERTEX = (inverse(MODEL_MATRIX) * vec4(world_v, 1.0)).xyz;
}

    TANGENT = vec3(1.0, 0.0, 0.0);
    BINORMAL = vec3(0.0, 0.0, 1.0);
}

// ==========================================
// FRAGMENT PASS
// ==========================================
void fragment() {
    vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
    vec3 world_view_dir = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
    
    float IN_PixelDepth = -VERTEX.z; 
    float raw_depth = texture(DEPTH_TEXTURE, SCREEN_UV).x;
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
    
    vec4 view_pos_scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    
    float safe_w = view_pos_scene.w;
    safe_w = sign(safe_w + 0.000001) * max(abs(safe_w), 0.00001);
    
    view_pos_scene.xyz /= safe_w;
    view_pos_scene.xyz = clamp(view_pos_scene.xyz, vec3(-10000.0), vec3(10000.0));
    
    float linear_scene_depth = max(-view_pos_scene.z, 0.0);
    
    vec4 world_pos_scene = INV_VIEW_MATRIX * vec4(view_pos_scene.xyz, 1.0);
    vec2 scene_uv = world_pos_scene.xz; 
    
    float depth_diff = max(linear_scene_depth - IN_PixelDepth, 0.0);
    
    float deep_ratio = clamp(depth_diff / max(abs(_Deep_Height), 0.001), 0.0, 1.0);
    vec4 deep_lerp = mix(_Deep_Color, _Shallow_Color, 1.0 - deep_ratio);
    
    float very_deep_ratio = clamp(depth_diff / max(abs(_Very_Deep_Height), 0.001), 0.0, 1.0);
    float very_deep_grad = clamp(very_deep_ratio * 2.0, 0.0, 1.0);
    vec4 water_base_color = mix(deep_lerp, _Very_Deep_Color, very_deep_grad);
    
    float caustics_intensity = Unity_Remap(_Caustics_Intensity, vec2(0.0, 1.0), vec2(0.0, 10.0));
    float voronoi_time = (TIME + 100.0) * 2.0;
    float voronoi_out, voronoi_cells;
    Unity_Voronoi_Deterministic(scene_uv, voronoi_time, 3.0, voronoi_out, voronoi_cells);
    float voronoi_pow = clamp(pow(voronoi_out, 4.0), 0.0, 1.0);
    
    vec2 caustics_uv_base = fract(scene_uv / max(_Caustics_Scale, 0.01));
    float caustics_speed = Unity_Remap(_Caustics_Speed, vec2(0.0, 1.0), vec2(0.0, 10.0));
    float current_frame = mod(floor(TIME * caustics_speed), 64.0);
    
    float frame_x = mod(current_frame, 8.0);
    float frame_y = floor(current_frame / 8.0);
    
    vec2 flipbook_uv = vec2(
        (caustics_uv_base.x + frame_x) / 8.0,
        (caustics_uv_base.y + (7.0 - frame_y)) / 8.0
    );
    
    float caustics_tex = texture(_SampleTexture2D_c5bda943a6134644bb954c2c5ced7db4_Texture_1_Texture2D, flipbook_uv).r;
    float caustics_val = _Caustics_Use_Voronoi_Noise > 0.5 ? voronoi_pow : caustics_tex;
    
    float caustics_fade = clamp(depth_diff * 0.1, 0.0, 1.0);
    float caustics_mask = (1.0 - caustics_fade) * caustics_fade * caustics_val * caustics_intensity;
    vec4 caustics_color = _Enable_Caustics > 0.5 ? clamp(_Caustics_Color * caustics_mask, 0.0, 1.0) : vec4(0.0);
    
    float shore_time = _Enable_Shore_Animation > 0.5 ? TIME : _Animation_Offset;
    float shore_speed = shore_time * _Shore_Wave_Speed;
    
    vec4 sn_col; float sn_r, sn_g, sn_b, sn_a;
    SG_TopDownProjection(_Noise_Texture, vec2(_Shore_Edge_Noise_Scale * 0.005), vec2(0.0), world_normal, world_pos, sn_col, sn_r, sn_g, sn_b, sn_a);
    
    float shore_wave = mod(shore_speed + clamp(sn_r, 0.0, 1.0), 1.0);
    float shore_return = Unity_Remap(_Shore_Wave_Return_Amount, vec2(0.0, 1.0), vec2(2.0, 1.0));
    float shore_sine = sin(shore_wave * (3.141593 / shore_return));
    float shore_dist = depth_diff + shore_sine;
    
    vec4 sfn_col; float sfn_r, sfn_g, sfn_b, sfn_a;
    SG_TopDownProjection(_Shore_Foam_Noise_Texture, vec2(_Shore_Foam_Noise_Scale * 0.005), vec2(0.0), world_normal, world_pos, sfn_col, sfn_r, sfn_g, sfn_b, sfn_a);
    
    float shore_foam_pow = clamp(pow(sfn_r, 0.2), 0.0, 1.0);
    float shore_wave_mask = clamp(shore_dist * shore_foam_pow, 0.0, 1.0);
    
    float shore_thick = Unity_Remap(clamp(_Shore_Wave_Thickness, 0.0, 1.0), vec2(0.0, 1.0), vec2(0.0, 0.99));
    float shore_remap1 = 1.0 - clamp(Unity_Remap(shore_wave, vec2(0.0, 1.0), vec2(-1.0, 1.0)), 0.0, 1.0);
    float shore_remap2 = 1.0 - clamp(Unity_Remap(shore_wave, vec2(0.0, 1.0), vec2(1.0, -3.0)), 0.0, 1.0);
    
    float shore_anim_mask = shore_remap1 * shore_remap2;
    float shore_final_mask = clamp(floor(shore_wave_mask + (shore_thick * shore_anim_mask)) - floor(shore_wave_mask), 0.0, 1.0);
    float shore_opacity = _Shore_Edge_Opacity / 1.5;
    vec4 shore_wave_color = _Enable_Shore_Wave_Foam > 0.5 ? (_Shore_Wave_Color_Tint * mix(0.0, shore_final_mask, shore_opacity)) : vec4(0.0);
    
    float edge_fade = depth_diff / max(_Shore_Edge_Thickness, 0.001);
    float edge_mask = 1.0 - clamp(pow(edge_fade, 2.0), 0.0, 1.0);
    vec4 shore_edge_color = _Enable_Shore_Wave_Foam > 0.5 ? (_Shore_Wave_Color_Tint * edge_mask * _Shore_Edge_Opacity) : vec4(0.0);
    
    float small_foam_fade = 1.0 - clamp(depth_diff / 2.0, 0.0, 1.0);
    vec4 ssf_col; float ssf_r, ssf_g, ssf_b, ssf_a;
    SG_TopDownProjection(_Noise_Texture, vec2(_Shore_Small_Foam_Tiling * 0.01), vec2(TIME * 0.003), world_normal, world_pos, ssf_col, ssf_r, ssf_g, ssf_b, ssf_a);
    
    float small_foam_val = clamp(pow(ssf_r * (small_foam_fade * 0.8) * 5.0, 20.0), 0.0, 1.0);
    float small_foam_op = _Shore_Small_Foam_Opacity / 3.0;
    vec4 shore_small_color = _Enable_Shore_Foam > 0.5 ? (_Shore_Foam_Color_Tint * mix(0.0, small_foam_val, small_foam_op)) : vec4(0.0);
    
    vec4 gf_col; float gf_r, gf_g, gf_b, gf_a;
    SG_TopDownProjection(_Noise_Texture, vec2(0.025), vec2(0.0), world_normal, world_pos, gf_col, gf_r, gf_g, gf_b, gf_a);
    
    float wave_y_frag; float wave_z_frag;
    SG_OceanWaveMask(_Ocean_Wave_Speed, _OceanWaveGradient, _Ocean_Wave_Height, vec3(1.0,0.0,1.0), 1.0, world_pos, vec3(TIME, 0.0, 0.0), wave_y_frag, wave_z_frag);
    
    float foam_amt = Unity_Remap(_Ocean_Foam_Amount, vec2(0.0, 1.0), vec2(5.0, 1.0));
    float foam_mask = clamp(pow(wave_z_frag, foam_amt), 0.0, 1.0);
    float global_foam_base = clamp(gf_r * (foam_mask * _Ocean_Foam_Amount), 0.0, 1.0);
    float global_fade = clamp(depth_diff * 0.05, 0.0, 1.0);
    
    vec4 ob_col; float ob_r, ob_g, ob_b, ob_a;
    SG_TopDownProjection(_Noise_Texture, vec2(_Ocean_Foam_Breakup_Tiling * 0.001), vec2(TIME * -0.002, 0.0), world_normal, world_pos, ob_col, ob_r, ob_g, ob_b, ob_a);
    
    float ocean_foam_val = clamp(pow(clamp(global_fade * (global_foam_base * (ob_r + 0.18)), 0.0, 1.0) * 20.0, 20.0), 0.0, 1.0);
    vec4 ocean_foam_color = _Enable_Global_Foam > 0.5 ? vec4(ocean_foam_val * _Ocean_Foam_Opacity) : vec4(0.0);
    
    vec2 scroll_uv = UV * _Scrolling_Texture_Tiling.xy + (1.0 - (_Scrolling_Texture_Direction.xy * TIME));
    vec4 scroll_tex = texture(_Scrolling_Texture, scroll_uv);
    vec4 scroll_color = _Scrolling_Texture_Tint * scroll_tex * _Scrolling_Texture_Opacity;
    
    float depth_fade_alpha_ratio = clamp(depth_diff / max(abs(_Deep_Height), 0.01), 0.0, 1.0);
    float base_water_opacity = mix(_Shallows_Opacity, 1.0, depth_fade_alpha_ratio);

    vec3 composition_rgb = water_base_color.rgb + caustics_color.rgb + shore_wave_color.rgb + shore_edge_color.rgb + shore_small_color.rgb + ocean_foam_color.rgb;
    vec3 final_rgb = _Enable_Top_Scrolling_Texture > 0.5 ? (composition_rgb + scroll_color.rgb) : composition_rgb;

    float total_foam_alpha = shore_wave_color.a + shore_edge_color.a + shore_small_color.a + ocean_foam_color.a;
    float final_alpha = base_water_opacity + total_foam_alpha;
    
    float dist_speed = Unity_Remap(_Distortion_Speed, vec2(0.0, 1.0), vec2(0.0, 0.001));
    vec2 dist_uv = UV + (vec2(dist_speed) * _Distortion_Direction.xy * TIME);
    float dist_size = Unity_Remap(_Distortion_Size, vec2(0.0, 1.0), vec2(0.0, 200.0));
    float dist_noise = Unity_GradientNoise_Deterministic(dist_uv, vec3(dist_size));
    float dist_str = Unity_Remap(_Distortion_Strength, vec2(0.0, 1.0), vec2(0.0, 0.05));
    
    vec2 screen_uv_dist = SCREEN_UV + vec2(dist_noise * dist_str);
    vec3 scene_color = texture(SCREEN_TEXTURE, screen_uv_dist).rgb * 0.65;
    
    vec3 out_color = _Enable_Distortion > 0.5 ? (final_rgb + scene_color) : final_rgb;
    
    float norm_tiling = Unity_Remap(_Normal_Tiling, vec2(0.0, 1.0), vec2(0.0, 0.04));
    vec2 pan_uv = SG_Panner(vec2(0.0), vec2(_Normal_Pan_Speed * 0.02), vec3(TIME, 0.0, 0.0));
    
    vec4 nn_col; float nn_r, nn_g, nn_b, nn_a;
    SG_TopDownProjection(_Noise_Texture, vec2(_Normal_Noise_Tiling * 0.01), vec2(0.0), world_normal, world_pos, nn_col, nn_r, nn_g, nn_b, nn_a);
    
    vec2 norm_uv1 = _Normal_Offset.xy + vec2(nn_r * _Normal_Noise_Intensity);
    vec2 norm_proj_uv1 = norm_uv1 + pan_uv;
    
    vec4 n1_col; float n1_r, n1_g, n1_b;
    SG_TopDownProjectionNormal(_Normal_Texture, vec2(norm_tiling), norm_proj_uv1, world_normal, world_pos, n1_col, n1_r, n1_g, n1_b);
    
    vec2 norm_proj_uv2 = norm_proj_uv1 * vec2(1.0, -1.0);
    vec4 n2_col; float n2_r, n2_g, n2_b;
    SG_TopDownProjectionNormal(_Normal_Texture, vec2(norm_tiling * 0.2), norm_proj_uv2, world_normal, world_pos, n2_col, n2_r, n2_g, n2_b);
    
    vec3 blended_normal = Unity_NormalBlend(n1_col.xyz, n2_col.xyz);
    
    float fresnel = Unity_FresnelEffect(world_normal, world_view_dir, _Fade_Distance);
    float fade = smoothstep(0.0, 1.0, 1.0 - (_Fade_Power * fresnel));
    float norm_fade = _Enable_Fresnel_Fade > 0.5 ? (fade * _Normal_Intensity) : _Normal_Intensity;
    
    vec3 final_normal = mix(vec3(0.0, 0.0, 1.0), blended_normal, norm_fade);
    vec3 out_normal = _Enable_Normals > 0.5 ? final_normal : vec3(0.0, 0.0, 1.0);
    
    ALBEDO = out_color;
    NORMAL_MAP = out_normal * 0.5 + 0.5; 
    METALLIC = _Metallic;
    ROUGHNESS = 1.0 - _Smoothness;
    SPECULAR = 0.5;
    
    float alpha_clip = clamp(final_alpha - (1.0 - _Base_Opacity), 0.0, 1.0);
    ALPHA = alpha_clip;
    
    ALPHA_SCISSOR_THRESHOLD = _AlphaClip > 0.5 ? 0.5 : 0.0;
}