FROM alpine
MAINTAINER Carlos Nunez <dev@carlosnunez.me>

RUN apk add curl
RUN curl -Lo /tmp/terraform.zip https://releases.hashicorp.com/terraform/0.14.2/terraform_0.14.2_linux_arm64.zip
RUN cd /tmp && unzip /tmp/terraform.zip && mv terraform /usr/local/bin

COPY ./scripts /scripts

ENTRYPOINT [ "terraform" ]
