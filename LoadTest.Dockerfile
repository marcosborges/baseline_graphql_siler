FROM blazemeter/taurus

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

RUN groupadd -g ${gid} ${group} && useradd -u ${uid} -G ${group} -s /bin/sh -D ${user}

#COPY .bzt-rc /.bzt-rc
 
USER ${user}
 
ENTRYPOINT ['']