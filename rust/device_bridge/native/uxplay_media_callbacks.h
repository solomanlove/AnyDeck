/* HTTP 视频回调由 raop 的全局上下文调用，不能按 RTSP 连接上下文解引用。 */
static void on_media_play(void *cls, const char *url, float position) {
    anydeck_uxplay_handle_t *h = cls;
    h->media_command(h->rust_context, 1, url, position);
}
static void on_media_scrub(void *cls, float position) {
    anydeck_uxplay_handle_t *h = cls;
    h->media_command(h->rust_context, 2, NULL, position);
}
static void on_media_rate(void *cls, float rate) {
    anydeck_uxplay_handle_t *h = cls;
    h->media_command(h->rust_context, 3, NULL, rate);
}
static void on_media_stop(void *cls) {
    anydeck_uxplay_handle_t *h = cls;
    h->media_command(h->rust_context, 4, NULL, 0);
}
static void on_media_info(void *cls, playback_info_t *info) {
    anydeck_uxplay_handle_t *h = cls;
    double values[5] = {0};
    h->media_info(h->rust_context, values);
    memset(info, 0, sizeof(*info));
    info->duration = values[4] ? -1.0 : values[0];
    info->position = values[1];
    info->rate = (float)values[2];
    info->ready_to_play = values[3] != 0;
    info->playback_buffer_empty = !info->ready_to_play;
    info->playback_buffer_full = info->ready_to_play;
    info->playback_likely_to_keep_up = info->ready_to_play;
    info->seek_duration = values[0];
}
static float on_media_playlist_remove(void *cls) {
    anydeck_uxplay_handle_t *h = cls;
    double values[5] = {0};
    h->media_info(h->rust_context, values);
    on_media_stop(cls);
    return (float)values[1];
}
