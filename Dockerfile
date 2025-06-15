# Reference: https://docs.aws.amazon.com/sagemaker/latest/dg/code-editor-custom-images-specifications.html
# Reference: https://qiita.com/moritalous/items/859c9977dd6b923472f1

# ---- 1. ベースイメージ固定 --------------------------------------------
# imageのバージョンを指定
# 選択可能なimageの一覧 : https://docs.aws.amazon.com/en_us/sagemaker/latest/dg/sagemaker-distribution.html
ARG BASE_TAG="latest-cpu"
FROM public.ecr.aws/sagemaker/sagemaker-distribution:${BASE_TAG}

ARG BASE_TAG
RUN echo "🚀Starting build img : public.ecr.aws/sagemaker/sagemaker-distribution:${BASE_TAG}"

ARG NB_USER="sagemaker-user"
ARG NB_UID=1000
ARG NB_GID=100
ENV MAMBA_USER=$NB_USER

USER root

# ---- 2. OS パッケージ ---------------------------------------------
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx curl ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---- 3. Code Editor ポート書き換え & Nginx 設定 ------------------
RUN sed -i 's/8888/18888/g' /usr/local/bin/start-code-editor \
    && sed -i '/^user www-data;/d' /etc/nginx/nginx.conf \
    && sed -i 's|/run/nginx.pid|/tmp/nginx.pid|g' /etc/nginx/nginx.conf \
    && rm -f /etc/nginx/sites-enabled/default

COPY nginx-proxy.conf /etc/nginx/conf.d/proxy.conf

# ---- 4. supervisord へ Nginx を追加 -------------------------------
RUN cat >> /etc/supervisor/conf.d/supervisord-code-editor.conf <<'EOF'
[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/var/log/nginx/stdout.log
stderr_logfile=/var/log/nginx/stderr.log
EOF

# ---- 5. パーミッション調整（1レイヤーで）-------------------------
RUN chown -R ${MAMBA_USER} /var/lib/nginx /var/log/nginx \
    && chmod -R 750 /var/lib/nginx /var/log/nginx


# ---- 6. 必須ポート公開 & ヘルスチェック -------------------------
EXPOSE 8888
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD curl -fs http://localhost:8888/ || exit 1

# ---- 7. 実行ユーザ & エントリポイント ----------------------------
USER $MAMBA_USER
ENTRYPOINT ["entrypoint-code-editor"]
