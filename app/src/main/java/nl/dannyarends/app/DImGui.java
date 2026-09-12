package nl.dannyarends.app;

import org.libsdl.app.SDLActivity;

/** DImGui entry point: thin subclass of SDL's Activity. */
public class DImGui extends SDLActivity {
  
  /** Native libraries in dlopen order; SDL3 first, main last. */
  @Override protected String[] getLibraries() {
    return new String[] { "SDL3", "SDL3_image", "SDL3_mixer", "freetype", "shaderc_shared", "spirv-cross-c-shared", "cimgui", "assimp", "main" };
  }
}
