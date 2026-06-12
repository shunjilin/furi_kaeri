FROM erlang:29.0-alpine AS build
COPY --from=ghcr.io/gleam-lang/gleam:v1.17.0-erlang-alpine /bin/gleam /bin/gleam
COPY . /app/
RUN cd /app && gleam export erlang-shipment

FROM erlang:29.0-alpine
RUN \
  addgroup --system webapp && \
  adduser --system webapp -g webapp
USER webapp
COPY --from=build /app/build/erlang-shipment /app
COPY --from=build --chown=webapp:webapp /app/priv /app/priv
WORKDIR /app

ENV GLEAM_ENV=production

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["run"]