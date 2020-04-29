FROM blazemeter/taurus

ENV user jenkins
 
RUN useradd -m -d /home/${user} ${user} \
 && chown -R ${user} /home/${user} 

COPY .bzt-rc /.bzt-rc
 
USER ${user}
 
ENTRYPOINT ['']