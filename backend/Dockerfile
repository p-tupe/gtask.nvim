FROM golang:1.25-alpine
WORKDIR /app
COPY * ./
RUN go mod tidy
RUN go build .
EXPOSE 3000
CMD [ "/app/gtask-auth-proxy" ]
