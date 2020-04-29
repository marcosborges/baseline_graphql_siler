FROM blazemeter/taurus

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

ENV user=$user
ENV group=$group
ENV uid=$uid
ENV gid=$gid

RUN groupadd -g ${gid} ${group} 
RUN useradd -m -d /home/${user} -G ${group} --uid ${uid} ${user} \
 && chown -R ${user} /home/${user} \
 && usermod -aG root $USER

#COPY .bzt-rc /.bzt-rc
 
USER ${user}
 
ENTRYPOINT ['']