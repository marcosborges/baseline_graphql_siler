FROM blazemeter/taurus

ENV user jenkins
 
RUN useradd -m -d /home/${user} ${user} \
 && chown -R ${user} /home/${user} 

RUN touch /.bzt-rc \ 
    && chmod 777 /.bzt-rc
 
 
USER ${user}
 
ENTRYPOINT ['']