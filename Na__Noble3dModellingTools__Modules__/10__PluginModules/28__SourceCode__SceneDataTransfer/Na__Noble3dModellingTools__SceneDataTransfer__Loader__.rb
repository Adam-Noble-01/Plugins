# =============================================================================
# NA NOBLE3D MODELLING TOOLS - SCENE DATA TRANSFER - LOADER
# =============================================================================
#
# FILE       : Na__Noble3dModellingTools__SceneDataTransfer__Loader__.rb
# NAMESPACE  : Na__Noble3dModellingTools::Na__SceneDataTransfer
# PURPOSE    : Load all Scene Data Transfer sub-modules in dependency order
# CREATED    : 2026
#
# LOAD ORDER MATTERS:
#   Schema      - constants every other file reads
#   Codec       - chunked dictionary read / write
#   Carrier     - depends on Schema and Codec
#   Domains     - one file per capture domain, no cross dependencies
#   Capture     - depends on Carrier, Codec and the domain serialisers
#   Reader      - depends on Carrier and Codec
#   Rebuilder   - depends on Schema and the domain serialisers
#   ModelState  - depends on Schema
#   Dialog, Run - depend on everything above
#
# =============================================================================

require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__Schema__'
require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__Codec__'
require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__Carrier__'

require_relative '01__DomainSerialisers/Na__SceneDataTransfer__ValueCodec__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__CameraDomain__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__AxesDomain__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__RenderingDomain__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__StyleFactory__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__ShadowDomain__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__SectionDomain__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__TagDomain__'
require_relative '01__DomainSerialisers/Na__SceneDataTransfer__HiddenGeometryDomain__'

require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__Capture__'
require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__Reader__'
require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__Rebuilder__'
require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__ModelState__'
require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__DialogManager__'
require_relative 'Na__Noble3dModellingTools__SceneDataTransfer__Run__'

# =============================================================================
# END OF FILE
# =============================================================================
