FROM blazemeter/taurus

ARG user=jenkins
ARG group=jenkins
ARG uid=1000
ARG gid=1000

RUN groupadd -g ${gid} ${group} 
RUN useradd −−home  /home/${user} −−uid ${uid} −−gid ${gid} ${user}
RUN chown -R ${user} /home/${user} 
RUN usermod -aG root ${user}

#COPY .bzt-rc /.bzt-rc
 
USER ${user}
 
ENTRYPOINT ['']
