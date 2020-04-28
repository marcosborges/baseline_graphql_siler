FROM blazemeter/taurus

ENV user jenkins
 
RUN useradd -m -d /home/${user} ${user} \
 && chown -R ${user} /home/${user}
 
USER ${user}
 
ENTRYPOINT ['']