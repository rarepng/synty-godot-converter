/******************************************************************************
POLYGON SHADER - General Purpose PBR Material Shader

Source: GodotShaders.com community shader
License: CC0 / MIT (check original source)

# Overview
Primary shader for props, terrain, buildings, and general materials.
Supports PBR workflow with optional features like triplanar mapping,
snow coverage, emission, and ambient occlusion.

# Required Global Uniforms
None required. All parameters are per-material.

# Key Features
- PBR texturing (albedo, normal, roughness, metallic, AO)
- Triplanar projection for seamless terrain/rocks
- Snow/frost coverage with height-based blending
- Emission support for glowing materials
- UV scaling and offset

# Parameter Groups
## Base Textures
- base_texture: Main albedo/color texture
- normal_texture: Surface normal map
- roughness_texture: Surface roughness
- metallic_texture: Metallic areas
- ao_texture: Ambient occlusion

## Material Properties
- smoothness: Surface smoothness (inverse of roughness)
- metallic: Metallic intensity
- color_tint: Color multiplier

## Triplanar (Optional)
- enable_triplanar: Use world-space projection
- triplanar_scale: Projection scale
- triplanar_sharpness: Blend sharpness

## Snow (Optional)
- enable_snow: Add snow coverage
- snow_amount: Coverage percentage
- snow_height_influence: Height-based snow accumulation

# Usage Notes
- Most versatile shader - use for anything that doesn't need special effects
- Enable triplanar for rocks, cliffs, terrain without UV seams
- Snow effect works best with enable_snow=true and adjusting snow_amount

# See Also
- docs/shader-reference.md for full parameter list
- docs/api/constants.md for Unity property mappings

# Original Implementation Notes
PolygonShader = Synty models static and tri-planar shader for Godot.
(C) Copyright 2025 - Giancarlo Niccolai
Published under MIT licence.
v. 1.1

Synty PolygonShader is used as a material shader for many of the
static Synty assets in the Polygon and related packages (e.g.
biomes).

Other than providing basic shading for texture, normal and emission,
it allows:

- Triplanar shading (texture, normal, emission).
- Overlay texture (for effect like i.e. blinking or selection).
- Ambient Occlusion
- Emission (flat/triplanar)
- Snow effects

In particular, instead of a "traditional" XYZ tri-planar shading,
the Synty shader provides top (Y), bottom (-Y) and Side (X and Z)
triplanar projection.

Note: This shader reproduces the behavior of the original Unity Synty
PolygonShader as closely as possible, but the normal tangent pipeline
is extremely different; I tried to replicate the visuals of the
application of the tri-planar normal map as closely as possible,
considering the different rendering pipelines.
******************************************************************************/
/******************************************************************************
POLYGON SHADER - General Purpose PBR Material Shader
******************************************************************************/
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, alpha_to_coverage_and_alpha_prepass;

group_uniforms Base_Settings;
uniform vec4 Color_Tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float Metallic : hint_range(0.0, 1.0) = 0.0;
uniform float Smoothness : hint_range(0.0, 1.0) = 0.0;

group_uniforms Textures;
uniform vec4 UVPan = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D Base_Texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 Base_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Base_Offset = vec4(0.0, 0.0, 0.0, 0.0);

uniform sampler2D Overlay_Texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 Overlay_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Overlay_Offset = vec4(0.0, 0.0, 0.0, 0.0);
uniform float Overlay_Intensity = 1.0;

uniform sampler2D Normal_Texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 Normal_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Normal_Offset = vec4(0.0, 0.0, 0.0, 0.0);
uniform float Normal_Intensity = 1.0;

group_uniforms Triplanar;
uniform bool Triplanar_Use_World_Space = true;
uniform bool Enable_Triplanar_Texture = false;
uniform sampler2D Triplanar_Texture_Top : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 Triplanar_Tiling_Top = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Offset_Top = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D Triplanar_Texture_Bottom : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 Triplanar_Tiling_Bottom = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Offset_Bottom = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D Triplanar_Texture_Side : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 Triplanar_Tiling_Side = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Offset_Side = vec4(0.0, 0.0, 0.0, 0.0);

uniform float Triplanar_Top_To_Side_Difference = 0.2;
uniform float Triplanar_Fade = 1.0;
uniform float Triplanar_Intensity = 1.0;
uniform float Top_Metallic = 0.0;
uniform float Side_Metallic = 0.0;
uniform float Bottom_Metallic = 0.0;
uniform float Top_Smoothness = 0.0;
uniform float Side_Smoothness = 0.0;
uniform float Bottom_Smoothness = 0.0;

group_uniforms Triplanar_Normals;
uniform bool Enable_Triplanar_Normals = false;
uniform sampler2D Triplanar_Normal_Texture_Top : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float Triplanar_Normal_Intensity_Top = 1.0;
uniform vec4 Triplanar_Normal_Tiling_Top = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Normal_Offset_Top = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D Triplanar_Normal_Texture_Bottom : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float Triplanar_Normal_Intensity_Bottom = 1.0;
uniform vec4 Triplanar_Normal_Tiling_Bottom = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Normal_Offset_Bottom = vec4(0.0, 0.0, 0.0, 0.0);
uniform sampler2D Triplanar_Normal_Texture_Side : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float Triplanar_Normal_Intensity_Side = 1.0;
uniform vec4 Triplanar_Normal_Tiling_Side = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Normal_Offset_Side = vec4(0.0, 0.0, 0.0, 0.0);
uniform float Triplanar_Normal_Top_To_Side_Difference = 0.2;
uniform float Triplanar_Normal_Fade = 0.0;

group_uniforms Emission;
uniform bool Enable_Triplanar_Emission = false;
uniform sampler2D Triplanar_Emission_Texture : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float Triplanar_Emission_Tiling = 0.25;
uniform float Triplanar_Emission_Blend = 1.0;
uniform float Triplanar_Emission_Intensity = 1.0;
uniform vec4 Triplanar_Emission_Color_Tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

uniform sampler2D Emission_Texture : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 Emission_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Emission_Offset = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Emission_Color_Tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

group_uniforms Alpine_Snow;
uniform bool Enable_Snow = false;
uniform bool Snow_Use_World_Up = true;
uniform vec4 Snow_Color : source_color = vec4(0.85, 0.85, 0.85, 1.0);
uniform float Snow_Metallic = 0.1;
uniform float Snow_Smoothness = 0.5;
uniform float Snow_Level = 0.0;
uniform float Snow_Transition = 1.0;
uniform float Snow_Angle_Threshold : hint_range(0.0, 1.0) = 0.42;
uniform float Snow_Transition_Threshold : hint_range(0.0, 1.0) = 1.0;
uniform bool Snow_Transition_Threshold_Steps = false;
uniform int Snow_Transition_Threshold_Step_Count = 4;
uniform bool Snow_Overrides_Normals = false;

group_uniforms AO_Settings;
uniform bool Enable_Ambient_Occlusion = false;
uniform bool Generate_From_Base_Normals = false;
uniform sampler2D AO_Texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float AO_Intensity = 1.0;
uniform vec4 AO_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 AO_Offset = vec4(0.0, 0.0, 0.0, 0.0);

group_uniforms Wave_Displacement;
uniform bool Enable_Wave = false;
uniform vec3 Wave_Direction_Vector = vec3(0.0, 1.0, 0.0);
uniform float Wave_Scale = 1.0;
uniform float Wave_Speed = 1.0;
uniform float Wave_Object_Offset = 0.0;

group_uniforms Extended_Pipeline_Properties;
uniform float AlphaClip = 1.0;
uniform float AlphaCutoff = 0.5;
uniform float AlphaToMask = 1.0;
uniform float Alpha_Clip_Threshold = 0.5;
uniform float Alpha_Transparency = 1.0;
uniform float Ambient_Occlusion = 1.0;
uniform float DetailNormalMapScale = 1.0;
uniform float Fade_Wave_Scale = 0.1;
uniform float Fade_Wave_To_Object_Origin = 0.0;
uniform float Fade_Wave_Vertical_Offset = 0.0;
uniform float FallOff = 10.0;
uniform float FallOff1 = 40.1;
uniform float FallOff2 = 100.0;
uniform float GlossMapScale = 1.0;
uniform float Parallax = 0.02;
uniform float Sea_Level = 0.0;
uniform float SmoothnessTextureChannel = 0.0;
uniform float Snow_Noise_Fade = 64.0;
uniform float Snow_Noise_Top_To_Side_Difference = 0.2;
uniform float Snow_Normal_Fade = 64.0;
uniform float Snow_Normal_Intensity = 1.0;
uniform float SpecularHighlights = 1.0;
uniform float Tiling = 0.04;
uniform float UVSec = 0.0;
uniform float WorkflowMode = 1.0;
uniform vec4 Specular_Color : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Alpha_Offset = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Alpha_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Snow_Metallic_Smoothness_Offset = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Snow_Metallic_Smoothness_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Snow_Noise_Offset = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Snow_Noise_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Snow_Normal_Offset = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Snow_Normal_Tiling = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Emission_Offset_Bottom = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Triplanar_Emission_Offset_Side = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Triplanar_Emission_Offset_Top = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 Triplanar_Emission_Tiling_Bottom = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Emission_Tiling_Side = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Triplanar_Emission_Tiling_Top = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 Wave_Noise_Tiling = vec4(1.0, 1.0, 0.0, 0.0);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_local_pos;
varying vec3 v_local_normal;

float remap(float value, vec2 in_min_max, vec2 out_min_max) {
    return out_min_max.x + (value - in_min_max.x) * (out_min_max.y - out_min_max.x) / (in_min_max.y - in_min_max.x);
}

vec3 unpack_normal(vec3 rgba) {
    return rgba * 2.0 - 1.0;
}

vec3 normal_strength(vec3 n, float strength) {
    return vec3(n.xy * strength, mix(1.0, n.z, clamp(strength, 0.0, 1.0)));
}

vec3 blend_normals(vec3 n1, vec3 n2) {
    return normalize(vec3(n1.xy + n2.xy, n1.z * n2.z));
}

vec2 apply_panner_tiling_offset(vec2 uv, vec2 pan_speed, vec4 tiling, vec4 offset, float time) {
    vec2 panned_uv = uv + (pan_speed * time);
    return (panned_uv * tiling.xy) + offset.xy;
}

void vertex() {
    v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
    v_local_pos = VERTEX;
    v_local_normal = NORMAL;
    
    if (Enable_Wave) {
        float wave_time = TIME * Wave_Speed + Wave_Object_Offset;
        float wave_val = sin(v_world_pos.x * Wave_Scale + wave_time) * cos(v_world_pos.z * Wave_Scale + wave_time);
        vec3 local_wave_dir = (inverse(MODEL_MATRIX) * vec4(Wave_Direction_Vector, 0.0)).xyz;
        VERTEX += local_wave_dir * wave_val * 0.1;
    }
}

void fragment() {
    vec3 t_pos = Triplanar_Use_World_Space ? v_world_pos : v_local_pos;
    vec3 t_normal = Triplanar_Use_World_Space ? v_world_normal : v_local_normal;

    vec3 abs_normal = abs(t_normal);
    
    float diff_sat = clamp(Triplanar_Top_To_Side_Difference, 0.0, 1.0);
    float diff_remap = remap(diff_sat, vec2(0.0, 1.0), vec2(0.25, 4.0));
    vec3 mod_normal = abs_normal * vec3(1.0, diff_remap, 1.0);
    
    float max_comp = max(mod_normal.x, max(mod_normal.y, mod_normal.z));
    mod_normal /= max(max_comp, 0.00001); 
    
    float fade_clamp = clamp(Triplanar_Fade, 0.001, 4096.0);
    vec3 pow_normal = pow(mod_normal, vec3(fade_clamp));
    vec3 tri_weights = pow_normal / dot(pow_normal, vec3(1.0));
    
    float is_top = step(0.0, t_normal.y);
    float top_mask = tri_weights.y * is_top;
    float bottom_mask = tri_weights.y * (1.0 - is_top);
    float side_mask = tri_weights.x + tri_weights.z;
    
    vec3 pos_adj = t_pos * vec3(1.0, 1.0, -1.0);
    vec3 sign_n = sign(t_normal);
    vec2 uv_side = vec2(pos_adj.z * -1.0 * sign_n.x, pos_adj.y);
    vec2 uv_top = vec2(pos_adj.x * sign_n.y, pos_adj.z);
    vec2 uv_bottom = vec2(pos_adj.x * sign_n.y, pos_adj.z); 
    
    vec4 base_tex = texture(Base_Texture, apply_panner_tiling_offset(UV, UVPan.xy, Base_Tiling, Base_Offset, TIME));
    
    vec4 raw_overlay = texture(Overlay_Texture, apply_panner_tiling_offset(UV, UVPan.xy, Overlay_Tiling, Overlay_Offset, TIME));
    vec4 overlay_tex = clamp(raw_overlay + vec4(1.0 - Overlay_Intensity), 0.0, 1.0);
    
    vec4 combined_base = base_tex * overlay_tex * Color_Tint;
    
    vec4 triplanar_color = vec4(1.0);
    if (Enable_Triplanar_Texture) {
        vec4 top_col = texture(Triplanar_Texture_Top, uv_top * 0.01 * Triplanar_Tiling_Top.xy + Triplanar_Offset_Top.xy);
        vec4 bot_col = texture(Triplanar_Texture_Bottom, uv_bottom * 0.01 * Triplanar_Tiling_Bottom.xy + Triplanar_Offset_Bottom.xy);
        vec4 side_col = texture(Triplanar_Texture_Side, uv_side * 0.01 * Triplanar_Tiling_Side.xy + Triplanar_Offset_Side.xy);
        
        vec4 raw_triplanar = top_col * top_mask + bot_col * bottom_mask + side_col * side_mask;
        triplanar_color = clamp(raw_triplanar + vec4(1.0 - Triplanar_Intensity), 0.0, 1.0);
    }
    
    vec4 final_albedo = combined_base * triplanar_color;
    
    vec3 snow_up_vec = Snow_Use_World_Up ? v_world_normal : v_local_normal;
    float snow_dot = max(0.0, snow_up_vec.y);
    
    float snow_fade = mix(0.35, 50.0, Snow_Level);
    float base_mask = pow(snow_dot, snow_fade) * Snow_Transition;
    
    float advanced_mask = smoothstep(Snow_Angle_Threshold - 0.1, Snow_Angle_Threshold + 0.1, snow_dot);
    float raw_snow_mask = base_mask * advanced_mask * Snow_Transition_Threshold;
    
    if (Snow_Transition_Threshold_Steps && Snow_Transition_Threshold_Step_Count > 0) {
        float steps = float(Snow_Transition_Threshold_Step_Count);
        raw_snow_mask = floor(raw_snow_mask * steps + 0.5) / steps;
    }
    
    float snow_mask = Enable_Snow ? clamp(raw_snow_mask, 0.0, 1.0) : 0.0;
    
    final_albedo = mix(final_albedo, Snow_Color, snow_mask);
    ALBEDO = final_albedo.rgb;
    ALPHA = base_tex.a;
    ALPHA_SCISSOR_THRESHOLD = 0.5;

    vec3 base_n = unpack_normal(texture(Normal_Texture, apply_panner_tiling_offset(UV, UVPan.xy, Normal_Tiling, Normal_Offset, TIME)).rgb);
    base_n = normal_strength(base_n, Normal_Intensity);
    
    vec3 tri_n = vec3(0.0, 0.0, 1.0);
    if (Enable_Triplanar_Normals) {
        float norm_diff_sat = clamp(Triplanar_Normal_Top_To_Side_Difference, 0.0, 1.0);
        float norm_diff_remap = remap(norm_diff_sat, vec2(0.0, 1.0), vec2(0.25, 4.0));
        vec3 norm_mod = abs_normal * vec3(1.0, norm_diff_remap, 1.0);
        
        float n_max_comp = max(norm_mod.x, max(norm_mod.y, norm_mod.z));
        norm_mod /= max(n_max_comp, 0.00001);
        
        float norm_fade = clamp(Triplanar_Normal_Fade, 0.001, 4096.0);
        vec3 norm_pow = pow(norm_mod, vec3(norm_fade));
        vec3 norm_weights = norm_pow / dot(norm_pow, vec3(1.0));
        
        float n_top_m = norm_weights.y * is_top;
        float n_bot_m = norm_weights.y * (1.0 - is_top);
        float n_side_m = norm_weights.x + norm_weights.z;
        
        vec3 top_norm = unpack_normal(texture(Triplanar_Normal_Texture_Top, uv_top * 0.01 * Triplanar_Normal_Tiling_Top.xy + Triplanar_Normal_Offset_Top.xy).rgb);
        top_norm = normal_strength(top_norm, Triplanar_Normal_Intensity_Top);
        
        vec3 bot_norm = unpack_normal(texture(Triplanar_Normal_Texture_Bottom, uv_bottom * 0.01 * Triplanar_Normal_Tiling_Bottom.xy + Triplanar_Normal_Offset_Bottom.xy).rgb);
        bot_norm = normal_strength(bot_norm, Triplanar_Normal_Intensity_Bottom);
        
        vec3 side_norm = unpack_normal(texture(Triplanar_Normal_Texture_Side, uv_side * 0.01 * Triplanar_Normal_Tiling_Side.xy + Triplanar_Normal_Offset_Side.xy).rgb);
        side_norm = normal_strength(side_norm, Triplanar_Normal_Intensity_Side);
        
        tri_n = top_norm * n_top_m + bot_norm * n_bot_m + side_norm * n_side_m;
    }
    
    vec3 blended_normals = blend_normals(base_n, tri_n);
    
    if (Enable_Snow && Snow_Overrides_Normals) {
        blended_normals = mix(blended_normals, vec3(0.0, 0.0, 1.0), snow_mask);
    }
    
    NORMAL_MAP = blended_normals * 0.5 + 0.5;

    float current_metallic = Metallic;
    float current_smoothness = Smoothness;
    
    if (Enable_Triplanar_Texture) {
        current_metallic = (top_mask * Top_Metallic) + (side_mask * Side_Metallic) + (bottom_mask * Bottom_Metallic);
        current_smoothness = (top_mask * Top_Smoothness) + (side_mask * Side_Smoothness) + (bottom_mask * Bottom_Smoothness);
    }
    
    METALLIC = mix(current_metallic, Snow_Metallic, snow_mask);
    ROUGHNESS = 1.0 - mix(current_smoothness, Snow_Smoothness, snow_mask);

    float ao_final = 1.0;
    if (Enable_Ambient_Occlusion) {
        float generated_ao = 1.0 - clamp((v_world_normal.x + v_world_normal.y) * v_world_normal.z, 0.0, 1.0);
        float tex_ao = texture(AO_Texture, UV * AO_Tiling.xy + AO_Offset.xy).r;
        float base_ao = Generate_From_Base_Normals ? generated_ao : tex_ao;
        ao_final = pow(base_ao, AO_Intensity);
    }
    AO = ao_final;

    vec3 final_emission = vec3(0.0);
    
    if (Enable_Triplanar_Emission) {
        vec3 tri_uv = t_pos * Triplanar_Emission_Tiling;
        vec3 blend_pow = pow(abs_normal, vec3(max(Triplanar_Emission_Blend, 0.001)));
        blend_pow /= dot(blend_pow, vec3(1.0));
        
        vec3 em_x = texture(Triplanar_Emission_Texture, tri_uv.zy).rgb;
        vec3 em_y = texture(Triplanar_Emission_Texture, tri_uv.xz).rgb;
        vec3 em_z = texture(Triplanar_Emission_Texture, tri_uv.xy).rgb;
        
        vec3 tri_em_col = em_x * blend_pow.x + em_y * blend_pow.y + em_z * blend_pow.z;
        final_emission += tri_em_col * Triplanar_Emission_Color_Tint.rgb * Triplanar_Emission_Intensity;
    }
    
    vec3 base_em = texture(Emission_Texture, apply_panner_tiling_offset(UV, UVPan.xy, Emission_Tiling, Emission_Offset, TIME)).rgb;
    final_emission += base_em * Emission_Color_Tint.rgb;
    
    EMISSION = final_emission;
}