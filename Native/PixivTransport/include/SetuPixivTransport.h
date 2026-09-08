#ifndef SETU_PIXIV_TRANSPORT_H
#define SETU_PIXIV_TRANSPORT_H
#include <stdint.h>
#include <stddef.h>
typedef struct SetuPixivCancellation SetuPixivCancellation;
typedef struct {
    int32_t status;
    const uint8_t *bytes;
    size_t length;
    const char *content_type;
    const char *error;
} SetuPixivResponse;
SetuPixivCancellation *setu_pixiv_cancellation_create(void);
void setu_pixiv_cancel(SetuPixivCancellation *value);
void setu_pixiv_cancellation_free(SetuPixivCancellation *value);
SetuPixivResponse *setu_pixiv_request(const char *json, const SetuPixivCancellation *cancellation);
void setu_pixiv_response_free(SetuPixivResponse *value);
typedef struct SetuPixivLogin SetuPixivLogin;
SetuPixivLogin *setu_pixiv_login_start(const char *password);
uint16_t setu_pixiv_login_port(const SetuPixivLogin *value);
const uint8_t *setu_pixiv_login_certificate(const SetuPixivLogin *value);
size_t setu_pixiv_login_certificate_length(const SetuPixivLogin *value);
uint32_t setu_pixiv_login_stage(const SetuPixivLogin *value);
void setu_pixiv_login_free(SetuPixivLogin *value);
#endif
