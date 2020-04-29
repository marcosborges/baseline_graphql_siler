FROM blazemeter/taurus

ENV user jenkins
 
RUN useradd -m -d /home/jenkins jenkins \
 && chown -R jenkins /home/jenkins \
 && usermod -aG root jenkins

#COPY .bzt-rc /.bzt-rc
 
USER jenkins
 
ENTRYPOINT ['']