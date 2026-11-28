extends Resource
class_name UndergroundAmbiance

## Ambiance du donjon : une raffinerie ensevelie sous le sable. Pas de ciel,
## une faible lumière chaude qui filtre par les fissures (la lumière
## directionnelle), une pénombre brune, de la poussière en suspension, et les
## lampes murales des salles comme vraies sources de lumière.
##
## Appliquée par le Dungeon au lancement sur le WorldEnvironment et la
## lumière directionnelle de la scène : rien à régler dans le .tscn.

@export_group("Fond et pénombre")
@export var background := Color("#0d0906")       ## ce qu'on voit hors des salles
## Pénombre froide : les zones hors des lampes virent au bleu-violet, ce
## qui fait ressortir les flaques de lumière orange.
@export var ambient := Color("#3a3358")          ## lumière diffuse de la grotte
@export var ambient_energy: float = 0.45

@export_group("Lumière des fissures")
@export var crack_light := Color(1.0, 0.78, 0.55)
@export var crack_energy: float = 0.16
## Ombres de la lumière des fissures. Coupées par défaut : sa direction
## fixe projetait des ombres sans rapport avec les lampes des salles. Les
## ombres viennent des lampes elles-mêmes.
@export var crack_shadows: bool = false

@export_group("Poussière")
@export var dust_color := Color("#3a2a1c")
@export var dust_density: float = 0.012
## Poussière volumétrique : les lampes y dessinent des halos. Remplace la
## brume simple (dust_density) quand elle est active.
@export var volumetric_dust: float = 0.035
@export var volumetric_dust_color := Color("#d9b48a")

@export_group("Image")
@export var exposure: float = 1.05
@export var glow: float = 0.7                     ## halo autour des lampes, yeux, écrans
@export var saturation: float = 1.15
@export var contrast: float = 1.1
@export var ambient_occlusion: bool = true        ## assombrit les coins : effet souterrain


func apply_to(env: Environment, sun: DirectionalLight3D) -> void:
	if env != null:
		env.background_mode = Environment.BG_COLOR
		env.background_color = background
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = ambient
		env.ambient_light_energy = ambient_energy

		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = exposure

		env.glow_enabled = glow > 0.0
		env.glow_intensity = glow
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.2   # seuls les points vraiment lumineux brillent

		env.volumetric_fog_enabled = volumetric_dust > 0.0
		env.volumetric_fog_density = volumetric_dust
		env.volumetric_fog_albedo = volumetric_dust_color
		env.volumetric_fog_emission = Color("#1a1020")
		env.fog_enabled = dust_density > 0.0 and volumetric_dust <= 0.0
		env.fog_light_color = dust_color
		env.fog_density = dust_density
		env.fog_sky_affect = 0.0

		env.adjustment_enabled = true
		env.adjustment_saturation = saturation
		env.adjustment_contrast = contrast

		env.ssao_enabled = ambient_occlusion
		env.ssao_intensity = 1.6

	if sun != null:
		sun.light_color = crack_light
		sun.light_energy = crack_energy
		sun.shadow_enabled = crack_shadows
