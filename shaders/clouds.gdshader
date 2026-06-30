/******************************************************************************
CLOUDS SHADER - Volumetric Cloud and Atmospheric Effects

Source: Synty ShaderGraph to Godot GDShader Translation
Pipeline: Unity URP (ShaderGraph) -> Godot 4 Forward+

# Math Verification
- Base/Top Color: Lerped based on light direction dot normal
- Fresnel/Rim: Stepped application isolated to the shadowed side of the clouds
- Scattering: Fresnel-based light scattering rim effect
- Alpha Blending: Cascades through lerps; shape preserved with depth_draw_opaque
- Displacement: Sinusoidal translation based on local X/Z and TIME
******************************************************************************/

shader_type spatial;
render_mode unshaded, blend_mix, depth_prepass_alpha, cull_disabled;

group_uniforms Color;
uniform vec4 top_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 base_color : source_color = vec4(0.705, 0.890, 1.0, 1.0);
uniform bool use_environment_override = false;

group_uniforms Lighting;
uniform vec3 light_direction_override = vec3(0.0, 0.0, 0.0);
uniform float light_intensity : hint_range(-1.0, 1.0) = 0.0;
uniform bool enable_fresnel = false;
uniform float fresnel_power = 0.6;
uniform vec4 fresnel_color : source_color = vec4(0.933, 0.198, 0.198, 1.0);

group_uniforms Lighting.Effects;
uniform bool enable_fog = false;
uniform float fog_density : hint_range(0.0, 1.0) = 0.2;
uniform bool enable_scattering = true;
uniform float scattering_multiplier = 0.0;
uniform float scattering_edge_dist : hint_range(0.0, 1.0) = 0.0;
uniform vec4 scattering_color : source_color = vec4(0.735, 0.534, 0.253, 1.0);

group_uniforms Vertex;
uniform float cloud_speed = 0.0;
uniform float cloud_strength = 0.0;

global uniform vec3 MainLightDirection;
global uniform vec4 SkyColor;
global uniform vec4 EquatorColor;
global uniform vec4 GroundColor;

void vertex() {
	float displacement = sin((VERTEX.x + VERTEX.z) + (TIME * cloud_speed)) * cloud_strength;
	VERTEX.y += displacement;
}

void fragment() {
	vec4 env_base_color = use_environment_override ? EquatorColor : base_color;
	vec4 env_top_color = use_environment_override ? SkyColor : top_color;
	vec4 env_fresnel_color = use_environment_override ? GroundColor : fresnel_color;
	vec4 env_scattering_color = use_environment_override ? EquatorColor : scattering_color;

	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_view = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);

	vec3 effective_light_dir = -(light_direction_override + MainLightDirection);
	float NdotL = dot(effective_light_dir, world_normal);
	
	float light_step = step(-light_intensity, NdotL);
	vec4 base_to_top = mix(env_base_color, env_top_color, light_step);

	float fresnel_base = 1.0 - clamp(dot(world_normal, world_view), 0.0, 1.0);
	
	float fresnel_step = step(1.0 - fresnel_power, fresnel_base);
	
	float fresnel_mask = (1.0 - light_step) * fresnel_step;
	vec4 with_fresnel = mix(base_to_top, env_fresnel_color, fresnel_mask);

	vec4 current_color = enable_fresnel ? with_fresnel : base_to_top;

	if (enable_scattering) {
		float scatter_fresnel = pow(fresnel_base, scattering_edge_dist);
		
		vec3 scatter_vec = MainLightDirection * scatter_fresnel;
		vec3 scatter_add = vec3(scattering_multiplier) + scatter_vec;
		
		current_color.rgb = mix(current_color.rgb, env_scattering_color.rgb, clamp(scatter_add, 0.0, 1.0));
	}

	ALBEDO = current_color.rgb;
	ALPHA = current_color.a;
}