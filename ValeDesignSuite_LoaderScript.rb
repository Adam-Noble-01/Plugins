# =============================================================================
# ValeDesignSuite - Loader Script
# =============================================================================
#
# NAMESPACE : ValeDesignSuite
# MODULE    : LoaderScript
# AUTHOR    : Adam Noble - Vale Garden Houses
# TYPE      : SketchUp 2026 Plugin Loader
# PURPOSE   : Entry point and registration for the ValeDesignSuite Plugin
# CREATED   : 20-May-2025
#
# DESCRIPTION:
# - This is the main loader script for the Vale Design Suite plugin
# - Serves as the entry point and registers the plugin with SketchUp
# - Points to the main plugin script file in the ValeDesignSuite subfolder
#
# USAGE NOTES: 
# - This file should be placed directly in the SketchUp Plugins folder
# - Required for proper plugin registration and loading
# 
# IMPORTANT CONSIDERATIONS: 
# - Minimal code should be placed in this file
# - Core functionality is implemented in the ValeDesignSuite subfolder
# - This file remains unencrypted even in signed extensions
#
# -----------------------------------------------------------------------------
#
# DEVELOPMENT LOG:
# 20-May-2025 - Version 0.0.1 - INITIAL SETUP
# - Created basic loader script structure
# - Implemented extension registration
#
# =============================================================================

# Load required Ruby libraries for extension registration
require 'sketchup.rb'
require 'extensions.rb'

# Define extension information
extension_name        = 'VGH |  Vale Design Suite'
extension_description = 'Custom tools for creating 3D models of Vale Garden Houses products'
extension_version     = '0.0.4'
extension_creator     = 'Adam Noble - Vale Garden Houses'
extension_copyright   = '© 2025 Vale Garden Houses'

# Define file paths
current_path = File.dirname(__FILE__)
loader_path = File.join(current_path, 'ValeDesignSuite', 'ValeDesignSuite_Core_PluginScript')

# Create the SketchUp extension object
vds_extension = SketchupExtension.new(
  extension_name,
  loader_path
)

# Set extension details
vds_extension.description = extension_description
vds_extension.version = extension_version
vds_extension.creator = extension_creator
vds_extension.copyright = extension_copyright

# Register the extension with SketchUp
# The 'true' parameter makes the extension enabled by default
Sketchup.register_extension(vds_extension, true)

# =============================================================================
# END OF FILE
# =============================================================================
