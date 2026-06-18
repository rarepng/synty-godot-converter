shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley,
    specular_schlick_ggx;

uniform sampler2D depth_texture : hint_depth_texture,
                                  repeat_disable,
                                  filter_nearest;
uniform sampler2D screen_texture : hint_screen_texture,
                                   repeat_disable,
                                   filter_linear_mipmap;

group_uniforms Base;
uniform vec4 base_color_multiplier : source_color = vec4(1.0);
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_albedo : source_color,
                                filter_linear_mipmap,
                                repeat_enable;
uniform sampler2D base_normal : hint_normal,
                                filter_linear_mipmap,
                                repeat_enable;
uniform float base_normal_intensity : hint_range(-2.0, 2.0) = 1.0;
uniform float base_tiling = 0.4;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.084;
uniform float base_specular_power : hint_range(0.0, 1.0) = 0.85;
uniform float metallic : hint_range(0.0, 1.0) = 0.239;
uniform float smoothness : hint_range(0.0, 1.0) = 0.456;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float base_opacity : hint_range(0.0, 1.0) = 1.0;

group_uniforms TopProjection;
uniform bool enable_top_projection = true;
uniform bool enable_triplanar = true;
uniform vec4 top_color_multiplier : source_color = vec4(1.0);
uniform sampler2D top_albedo : source_color,
                               filter_linear_mipmap,
                               repeat_enable;
uniform sampler2D top_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float top_normal_intensity : hint_range(-2.0, 2.0) = 1.0;
uniform float top_tiling = 0.2;
uniform float top_metallic : hint_range(0.0, 1.0) = 0.0;
uniform float top_specular_power : hint_range(0.0, 1.0) = 0.2;
uniform float top_smoothness : hint_range(0.0, 1.0) = 0.2;
uniform float top_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float spread : hint_range(0.0, 1.0) = 0.292;
uniform float fade_amount : hint_range(0.0, 100.0) = 38.6;
uniform float falloff : hint_range(0.0, 20.0) = 10.0;

group_uniforms Refraction;
uniform bool enable_refraction = true;
uniform sampler2D refraction_texture : source_color,
                                       filter_linear_mipmap,
                                       repeat_enable;
uniform sampler2D refraction_height : filter_linear_mipmap, repeat_enable;
uniform vec4 refraction_color : source_color = vec4(0.07, 0.09, 0.31, 1.0);
uniform float refraction_power : hint_range(0.0, 10.0) = 2.0;
uniform float refraction_tiling = 5.0;
uniform float amplitude = -50.0;

group_uniforms DepthFading;
uniform bool enable_depth = true;
uniform bool inner_distortion = true;
uniform float noise_tiling = 22.45;
uniform float inner_distortion_power : hint_range(0.0, 1.0) = 0.02;
uniform vec4 shallow_color : source_color = vec4(0.16, 0.27, 0.45, 1.0);
uniform vec4 deep_color : source_color = vec4(0.0, 0.05, 0.28, 1.0);
uniform float shallow_power : hint_range(0.0, 10.0) = 3.51;
uniform float deep_power : hint_range(0.0, 10.0) = 6.72;
uniform float depth_power_multiplier : hint_range(0.0, 5.0) = 1.1;

group_uniforms Fresnel;
uniform bool enable_side_fresnel = true;
uniform vec4 fresnel_color : source_color = vec4(0.36, 1.0, 1.5, 1.0);
uniform float fresnel_power : hint_range(0.0, 10.0) = 4.85;
uniform float fresnel_border : hint_range(0.0, 20.0) = 9.62;

varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 view_dir;

void vertex() {
  world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
  world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

  vec3 cam_pos = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
  view_dir = normalize(cam_pos - world_pos);
}

vec2 hash2(vec2 p) {
  p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
  return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float gradient_noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
                 dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
             mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
                 dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
             u.y) +
         0.5;
}

void fragment() {
  vec3 blend = abs(world_normal);
  blend = pow(blend, vec3(4.0));
  blend /= dot(blend, vec3(1.0));

  float top_mask =
      pow(clamp(world_normal.y + spread, 0.0, 1.0), max(fade_amount, 0.001));

  vec4 base_x = texture(base_albedo, world_pos.zy * base_tiling);
  vec4 base_y = texture(base_albedo, world_pos.xz * base_tiling);
  vec4 base_z = texture(base_albedo, world_pos.xy * base_tiling);
  vec4 base_triplanar = base_x * blend.x + base_y * blend.y + base_z * blend.z;

  vec4 top_y = texture(top_albedo, world_pos.xz * top_tiling);
  vec4 mixed_triplanar = base_x * blend.x + top_y * blend.y + base_z * blend.z;

  vec4 base_sampled = base_triplanar * base_color_multiplier;
  vec4 top_sampled = mixed_triplanar * top_color_multiplier;
  vec4 mixed_sampled = mixed_triplanar * base_color_multiplier;

  vec4 albedo_top = mix(mixed_sampled, top_sampled, top_mask);
  vec4 albedo_final;

  if (enable_top_projection) {
    albedo_final = albedo_top;
  } else {
    albedo_final = base_sampled;
  }

  if (!enable_triplanar) {
    albedo_final = base_color;
  }

  float noise = gradient_noise(UV * noise_tiling);
  float inner_fresnel = pow(1.0 - clamp(dot(world_normal, view_dir), 0.0, 1.0),
                            inner_distortion_power);
  float depth_wobble = (1.0 - inner_fresnel) * noise;
  if (!inner_distortion)
    depth_wobble = 0.0;

  float depth_raw = texture(depth_texture, SCREEN_UV).r;
  vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
  vec4 v_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
  v_pos.xyz /= v_pos.w;

  float safe_deep_power = max(deep_power, 0.001);
  float safe_shallow_power = max(shallow_power, 0.001);

  float depth_diff = max(0.0, -v_pos.z + VERTEX.z - (depth_wobble * 2.0));

  float deep_fade = clamp(depth_diff / safe_deep_power, 0.0, 1.0);
  vec4 deep_c = deep_color * (1.0 - deep_fade);

  float shallow_fade = clamp(depth_diff / safe_shallow_power, 0.0, 1.0);
  vec4 shallow_c = shallow_color * (1.0 - shallow_fade);

  vec4 depth_added = deep_c + shallow_c;
  depth_added = mix(depth_added, vec4(0.0), top_mask);
  depth_added *= depth_power_multiplier;

  vec4 color_with_depth = albedo_final;
  if (enable_depth) {
    color_with_depth += depth_added;
  }

  float side_fresnel =
      pow(1.0 - clamp(dot(world_normal, view_dir), 0.0, 1.0), fresnel_border);
  vec4 fresnel_c = fresnel_color * side_fresnel * fresnel_power;

  vec4 output_color =
      mix(color_with_depth, color_with_depth + fresnel_c, 1.0 - top_mask);
  if (!enable_triplanar || !enable_top_projection || !enable_side_fresnel) {
    output_color = color_with_depth;
  }

  vec3 nb_x = texture(base_normal, world_pos.zy * base_tiling).xyz;
  vec3 nb_y = texture(base_normal, world_pos.xz * base_tiling).xyz;
  vec3 nb_z = texture(base_normal, world_pos.xy * base_tiling).xyz;
  vec3 nrm_base = normalize(nb_x * blend.x + nb_y * blend.y + nb_z * blend.z);
  nrm_base.xy *= base_normal_intensity;

  vec3 nt_y = texture(top_normal, world_pos.xz * top_tiling).xyz;
  vec3 nrm_top = normalize(nb_x * blend.x + nt_y * blend.y + nb_z * blend.z);
  nrm_top.xy *= top_normal_intensity;

  vec3 final_nrm = mix(nrm_base, nrm_top, top_mask);
  if (enable_triplanar) {
    NORMAL = normalize((VIEW_MATRIX * vec4(final_nrm, 0.0)).xyz);
  }

  vec2 parallax_uv = UV * refraction_tiling;
  float height = texture(refraction_height, parallax_uv).r;

  vec3 safe_tangent = length(TANGENT) > 0.01 ? TANGENT : vec3(1.0, 0.0, 0.0);
  vec3 safe_binormal = length(BINORMAL) > 0.01 ? BINORMAL : vec3(0.0, 1.0, 0.0);
  vec3 view_dir_ts = normalize(vec3(
      dot(VIEW, safe_tangent), dot(VIEW, safe_binormal), dot(VIEW, NORMAL)));

  vec2 offset = view_dir_ts.xy * vec2(1.0, -1.0) * (height * amplitude * 0.01);

  vec4 refr_tex = texture(refraction_texture, parallax_uv + offset);
  vec3 emission = refraction_color.rgb * refr_tex.rgb * refraction_power;

  if (!enable_refraction)
    emission = vec3(0.0);
  emission = mix(vec3(0.0), emission, 1.0 - top_mask);

  float out_metallic = mix(base_metallic, top_metallic, top_mask);
  if (!enable_top_projection)
    out_metallic = base_metallic;
  if (!enable_triplanar)
    out_metallic = metallic;

  float out_smoothness = mix(base_specular_power, top_specular_power, top_mask);
  if (!enable_top_projection)
    out_smoothness = base_specular_power;
  if (!enable_triplanar)
    out_smoothness = smoothness;

  float out_alpha = mix(opacity, top_opacity, top_mask);

  ALBEDO = output_color.rgb;
  EMISSION = emission;
  METALLIC = out_metallic;
  ROUGHNESS = clamp(1.0 - out_smoothness, 0.0, 1.0);
  ALPHA = out_alpha;
}