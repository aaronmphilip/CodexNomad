FROM golang:1.22-alpine AS build
WORKDIR /src
COPY services/relay/go.mod services/relay/go.sum* ./
RUN go mod download
COPY services/relay ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/codexnomad-relay ./cmd/relay

FROM alpine:3.20
RUN adduser -D -H codexnomad
USER codexnomad
COPY --from=build /out/codexnomad-relay /usr/local/bin/codexnomad-relay
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/codexnomad-relay"]
