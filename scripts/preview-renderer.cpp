// Offscreen OpenGL ES preview of already-validated, bundled HWS shaders.
// Never run automatically on downloaded or user-supplied GLSL.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl32.h>

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace {

std::string readText(const std::filesystem::path& path) {
    if (std::filesystem::file_size(path) > 1024 * 1024)
        throw std::runtime_error("shader exceeds the 1 MiB preview limit");
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("cannot open shader: " + path.string());
    return {std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>()};
}

GLuint compile(GLenum type, const std::string& source) {
    const GLuint shader = glCreateShader(type);
    const char* text = source.c_str();
    glShaderSource(shader, 1, &text, nullptr);
    glCompileShader(shader);
    GLint success = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (success == GL_TRUE) return shader;
    GLint length = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
    std::string log(static_cast<std::size_t>(std::max(1, length)), '\0');
    glGetShaderInfoLog(shader, length, nullptr, log.data());
    glDeleteShader(shader);
    throw std::runtime_error("shader compilation failed: " + log);
}

GLuint link(GLuint vertex, GLuint fragment) {
    const GLuint program = glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glLinkProgram(program);
    GLint success = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (success == GL_TRUE) return program;
    GLint length = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
    std::string log(static_cast<std::size_t>(std::max(1, length)), '\0');
    glGetProgramInfoLog(program, length, nullptr, log.data());
    glDeleteProgram(program);
    throw std::runtime_error("shader link failed: " + log);
}

void setUniforms(GLuint program, int width, int height, float progress) {
    glUseProgram(program);
    const auto uniform = [program](const char* name) { return glGetUniformLocation(program, name); };
    glUniform1i(uniform("tex"), 0);
    glUniform1f(uniform("progress"), progress);
    glUniform1f(uniform("seed"), 0.41F);
    glUniform2f(uniform("surface_size"), static_cast<float>(width), static_cast<float>(height));
    glUniform2f(uniform("resolution"), static_cast<float>(width), static_cast<float>(height));
    glUniform4f(uniform("window_rect"), 0.F, 0.F, 1.F, 1.F);
}

void writeFrame(const std::filesystem::path& directory, const std::string& event,
                int index, int width, int height, const std::vector<std::uint8_t>& pixels) {
    std::ostringstream name;
    name << event << '-' << std::setw(2) << std::setfill('0') << index << ".rgba";
    std::ofstream stream(directory / name.str(), std::ios::binary);
    if (!stream) throw std::runtime_error("cannot create preview frame");
    const std::size_t rowBytes = static_cast<std::size_t>(width) * 4;
    for (int row = height - 1; row >= 0; --row)
        stream.write(reinterpret_cast<const char*>(pixels.data() + row * rowBytes),
                     static_cast<std::streamsize>(rowBytes));
    if (!stream) throw std::runtime_error("cannot write preview frame");
}

void render(const std::filesystem::path& openPath, const std::filesystem::path& closePath,
            const std::filesystem::path& texturePath, const std::filesystem::path& outputDir,
            int width, int height, int steps) {
    const EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_SURFACELESS_MESA,
                                                     EGL_DEFAULT_DISPLAY, nullptr);
    if (display == EGL_NO_DISPLAY || eglInitialize(display, nullptr, nullptr) != EGL_TRUE)
        throw std::runtime_error("surfaceless EGL display unavailable");
    if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE)
        throw std::runtime_error("cannot bind OpenGL ES API");
    const EGLint configAttributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE
    };
    EGLConfig config = nullptr;
    EGLint configCount = 0;
    if (eglChooseConfig(display, configAttributes, &config, 1, &configCount) != EGL_TRUE
            || configCount != 1)
        throw std::runtime_error("RGBA8 OpenGL ES pbuffer unavailable");
    const EGLint surfaceAttributes[] = {EGL_WIDTH, width, EGL_HEIGHT, height, EGL_NONE};
    const EGLSurface surface = eglCreatePbufferSurface(display, config, surfaceAttributes);
    if (surface == EGL_NO_SURFACE) throw std::runtime_error("cannot create EGL pbuffer");
    const EGLint contextAttributes[] = {
        EGL_CONTEXT_MAJOR_VERSION_KHR, 3, EGL_CONTEXT_MINOR_VERSION_KHR, 2, EGL_NONE
    };
    const EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttributes);
    if (context == EGL_NO_CONTEXT || eglMakeCurrent(display, surface, surface, context) != EGL_TRUE)
        throw std::runtime_error("OpenGL ES 3.2 context unavailable");

    const std::string vertexSource = R"(#version 320 es
layout(location = 0) in vec2 position;
out vec2 v_texcoord;
void main() {
    v_texcoord = (position + 1.0) * 0.5;
    gl_Position = vec4(position, 0.0, 1.0);
})";
    const GLuint vertex = compile(GL_VERTEX_SHADER, vertexSource);
    const GLuint openFragment = compile(GL_FRAGMENT_SHADER, readText(openPath));
    const GLuint closeFragment = compile(GL_FRAGMENT_SHADER, readText(closePath));
    const GLuint openProgram = link(vertex, openFragment);
    const GLuint closeProgram = link(vertex, closeFragment);
    glDeleteShader(vertex);
    glDeleteShader(openFragment);
    glDeleteShader(closeFragment);

    const std::size_t byteCount = static_cast<std::size_t>(width) * height * 4;
    if (std::filesystem::file_size(texturePath) != byteCount)
        throw std::runtime_error("synthetic texture has the wrong size");
    std::vector<std::uint8_t> topDown(byteCount);
    std::ifstream textureStream(texturePath, std::ios::binary);
    textureStream.read(reinterpret_cast<char*>(topDown.data()),
                       static_cast<std::streamsize>(byteCount));
    if (!textureStream) throw std::runtime_error("cannot read synthetic texture");
    std::vector<std::uint8_t> bottomUp(byteCount);
    const std::size_t rowBytes = static_cast<std::size_t>(width) * 4;
    for (int row = 0; row < height; ++row)
        std::copy_n(topDown.data() + static_cast<std::size_t>(height - 1 - row) * rowBytes,
                    rowBytes, bottomUp.data() + static_cast<std::size_t>(row) * rowBytes);

    GLuint texture = 0;
    glGenTextures(1, &texture);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, bottomUp.data());
    const GLfloat triangle[] = {-1.F, -1.F, 3.F, -1.F, -1.F, 3.F};
    GLuint vertexArray = 0;
    GLuint buffer = 0;
    glGenVertexArrays(1, &vertexArray);
    glBindVertexArray(vertexArray);
    glGenBuffers(1, &buffer);
    glBindBuffer(GL_ARRAY_BUFFER, buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(triangle), triangle, GL_STATIC_DRAW);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, nullptr);
    glEnableVertexAttribArray(0);
    glViewport(0, 0, width, height);
    glDisable(GL_BLEND);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    std::vector<std::uint8_t> pixels(byteCount);
    for (const auto& [event, program] : std::vector<std::pair<std::string, GLuint>>{
             {"open", openProgram}, {"close", closeProgram}}) {
        for (int index = 0; index < steps; ++index) {
            const float progress = static_cast<float>(index) / static_cast<float>(steps - 1);
            setUniforms(program, width, height, progress);
            glClearColor(0.F, 0.F, 0.F, 0.F);
            glClear(GL_COLOR_BUFFER_BIT);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
            if (glGetError() != GL_NO_ERROR) throw std::runtime_error("OpenGL preview readback failed");
            writeFrame(outputDir, event, index, width, height, pixels);
        }
    }
    glDeleteBuffers(1, &buffer);
    glDeleteVertexArrays(1, &vertexArray);
    glDeleteTextures(1, &texture);
    glDeleteProgram(openProgram);
    glDeleteProgram(closeProgram);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, surface);
    eglTerminate(display);
}

} // namespace

int main(int argc, char** argv) {
    try {
        if (argc != 8) throw std::runtime_error(
            "usage: preview-renderer OPEN CLOSE TEXTURE.rgba OUTPUT_DIR WIDTH HEIGHT STEPS");
        const int width = std::stoi(argv[5]);
        const int height = std::stoi(argv[6]);
        const int steps = std::stoi(argv[7]);
        if (width < 1 || width > 1024 || height < 1 || height > 1024
                || steps < 2 || steps > 30 || !std::filesystem::is_directory(argv[4]))
            throw std::runtime_error("invalid preview dimensions, steps, or output directory");
        render(argv[1], argv[2], argv[3], argv[4], width, height, steps);
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
