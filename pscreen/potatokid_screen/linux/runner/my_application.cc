#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <stdlib.h>
#include <string.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // 视图与音量通道（音量通道需要 messenger，来自 view 的 engine）。
  FlView* view;
  FlMethodChannel* volume_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ---------- 系统音量：通过 pactl 操作默认 sink（PulseAudio 与
// pipewire-pulse 均支持），失败返回 FALSE，由调用方转成错误响应。 ----------

// 执行 `pactl <args>`，成功时 *stdout_out 需 g_free。
static gboolean run_pactl(const gchar* args, gchar** stdout_out) {
  gchar* cmd = g_strconcat("pactl ", args, nullptr);
  gchar* std_out = nullptr;
  gchar* std_err = nullptr;
  gint status = 0;
  gboolean spawned = g_spawn_command_line_sync(
      cmd, &std_out, &std_err, &status, nullptr);
  g_free(cmd);
  g_free(std_err);
  if (!spawned || status != 0) {
    g_free(std_out);
    return FALSE;
  }
  *stdout_out = std_out;
  return TRUE;
}

// 解析 pactl 输出里第一个 "NN%" 前的整数（Volume: front-left: 65536 / 100% ...）。
static gint parse_first_percent(const gchar* text) {
  const gchar* pct = strchr(text, '%');
  if (pct == nullptr) return -1;
  const gchar* end = pct;
  while (end > text && g_ascii_isdigit(*(end - 1))) end--;
  if (end == pct) return -1;
  return (gint)g_ascii_strtoll(end, nullptr, 10);
}

// getVolume：成功返回 0-100，失败返回 -1。
static gint read_volume_percent() {
  gchar* out = nullptr;
  if (!run_pactl("get-sink-volume @DEFAULT_SINK@", &out)) return -1;
  gint percent = parse_first_percent(out);
  g_free(out);
  return percent < 0 ? -1 : MIN(percent, 100);
}

static gboolean set_volume_delta(const gchar* delta) {
  gchar* out = nullptr;
  gchar* args = g_strconcat("set-sink-volume @DEFAULT_SINK@ ", delta, nullptr);
  gboolean ok = run_pactl(args, &out);
  g_free(args);
  g_free(out);
  return ok;
}

static gboolean toggle_mute() {
  gchar* out = nullptr;
  gboolean ok = run_pactl("set-sink-mute @DEFAULT_SINK@ toggle", &out);
  g_free(out);
  return ok;
}

// ---------- MethodChannel 回调（方法名与 Android 宿主一致） ----------

static void volume_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* name = fl_method_call_get_name(method_call);

  if (strcmp(name, "volumeUp") == 0) {
    response = set_volume_delta("+2%")
                   ? FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr))
                   : FL_METHOD_RESPONSE(fl_method_error_response_new(
                         "NO_AUDIO", "pactl failed", nullptr));
  } else if (strcmp(name, "volumeDown") == 0) {
    response = set_volume_delta("-2%")
                   ? FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr))
                   : FL_METHOD_RESPONSE(fl_method_error_response_new(
                         "NO_AUDIO", "pactl failed", nullptr));
  } else if (strcmp(name, "toggleMute") == 0) {
    response = toggle_mute()
                   ? FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr))
                   : FL_METHOD_RESPONSE(fl_method_error_response_new(
                         "NO_AUDIO", "pactl failed", nullptr));
  } else if (strcmp(name, "getVolume") == 0) {
    gint percent = read_volume_percent();
    response = percent < 0
                   ? FL_METHOD_RESPONSE(fl_method_error_response_new(
                         "NO_AUDIO", "pactl failed", nullptr))
                   : FL_METHOD_RESPONSE(fl_method_success_response_new(
                         fl_value_new_int(percent)));
  } else {
    // 其余方法（getDeviceModel/getAndroidId/...）交回 Dart 兜底。
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to send response: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "potatokid_screen");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "potatokid_screen");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // 注册系统音量通道（在插件注册之后，engine 已就绪）。
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->volume_channel =
      fl_method_channel_new(messenger, "potatokid/volume",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->volume_channel, volume_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->volume_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
