FROM azul/zulu-openjdk

# install tomcat
ENV TOMCAT_MAJOR_VERSION 8
ENV TOMCAT_VERSION 8.0.30
RUN apt-get update \
  && apt-get -y install curl \
  && curl http://archive.apache.org/dist/tomcat/tomcat-$TOMCAT_MAJOR_VERSION/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz \
       | tar xz -C /usr/share \
  && mv /usr/share/apache-tomcat-$TOMCAT_VERSION /usr/share/tomcat \
  && rm -r /usr/share/tomcat/webapps/* \
  && apt-get -y purge --auto-remove curl \
  && rm -r /var/lib/apt/lists/*

# install mariadb
ENV MARIADB_MAJOR_VERSION 10.1
RUN apt-get update \
  && apt-get -y install software-properties-common \
  && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0xcbcb082a1bb943db \
  && echo "deb http://ftp.osuosl.org/pub/mariadb/repo/$MARIADB_MAJOR_VERSION/ubuntu trusty main" \
       > /etc/apt/sources.list.d/mariadb.list \
  && apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get -y install mariadb-server \
  && rm -r /var/lib/apt/lists/*

# set mariadb password
RUN /etc/init.d/mysql start \
  && mysqladmin -u root password password \
  && /etc/init.d/mysql stop

# create mysql user for heatclinic
RUN /etc/init.d/mysql start \
  && echo "create user heatclinic@localhost identified by 'heatclinic';" | mysql --user=root --password=password \
  && echo "create database heatclinic;" | mysql --user=root --password=password \
  && echo "grant all privileges on heatclinic.* to heatclinic@localhost;" | mysql --user=root --password=password \
  && /etc/init.d/mysql stop

# build and install heatclinic war
ENV MAVEN_MAJOR_VERSION 3
ENV MAVEN_VERSION 3.3.9
ENV HEATCLINIC_VERSION 4.0.5-GA
COPY ehcache.xml /
RUN apt-get update \
  && apt-get -y install curl git \
  && curl http://archive.apache.org/dist/maven/maven-$MAVEN_MAJOR_VERSION/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz \
       | tar xz -C /usr/share \
  && mv /usr/share/apache-maven-$MAVEN_VERSION /usr/share/maven \
  && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn \
  && git clone https://github.com/BroadleafCommerce/DemoSite.git heatclinic \
  && (cd heatclinic && git checkout broadleaf-$HEATCLINIC_VERSION) \
  # set custom caching for demo purposes
  && cp ehcache.xml heatclinic/site/src/main/resources/bl-override-ehcache.xml \
  && (cd heatclinic && mvn package) \
  && mkdir /usr/share/tomcat/heatclinic \
  && cp heatclinic/lib/spring-instrument-*.RELEASE.jar /usr/share/tomcat/heatclinic/spring-instrument.jar \
  && cp heatclinic/site/target/mycompany.war /usr/share/tomcat/webapps/ROOT.war \
  && cp heatclinic/lib/tomcat-server-conf/context.xml /usr/share/tomcat/conf \
  && rm ehcache.xml \
  && rm -r heatclinic \
  && rm -r ~/.m2 \
  && rm -r /usr/share/maven \
  && rm /usr/bin/mvn \
  && apt-get -y purge --auto-remove curl git \
  && rm -r /var/lib/apt/lists/*

# install mariadb jdbc driver
ENV MARIADB_JDBC_DRIVER_VERSION 1.3.2
RUN apt-get update \
  && apt-get -y install curl \
  && curl http://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/$MARIADB_JDBC_DRIVER_VERSION/mariadb-java-client-$MARIADB_JDBC_DRIVER_VERSION.jar \
       > /usr/share/tomcat/lib/maria-java-client-$MARIADB_JDBC_DRIVER_VERSION.jar \
  && apt-get -y purge --auto-remove curl \
  && rm -r /var/lib/apt/lists/*

# create heatclinic database
ENV HEATCLINIC_OPTS \
  -javaagent:/usr/share/tomcat/heatclinic/spring-instrument.jar \
  -Ddatabase.url=jdbc:mysql://localhost:3306/heatclinic?useUnicode=true\\&characterEncoding=utf8 \
  -Ddatabase.user=heatclinic \
  -Ddatabase.password=heatclinic \
  -Ddatabase.driver=org.mariadb.jdbc.Driver \
  -Dproperty-shared-override=/usr/share/tomcat/heatclinic/heatclinic.properties
COPY heatclinic-createdb.properties /usr/share/tomcat/heatclinic/heatclinic.properties
RUN /etc/init.d/mysql start \
  && CATALINA_OPTS=$HEATCLINIC_OPTS /usr/share/tomcat/bin/catalina.sh start \
  && until [ -e /usr/share/tomcat/logs/catalina.out ] && grep 'Server startup' /usr/share/tomcat/logs/catalina.out; \
       do tail /usr/share/tomcat/logs/catalina.out && sleep 1; done \
  && /usr/share/tomcat/bin/catalina.sh stop \
  && /etc/init.d/mysql stop \
  && rm -r /usr/share/tomcat/webapps/ROOT \
  && rm /usr/share/tomcat/logs/*

COPY heatclinic.properties /usr/share/tomcat/heatclinic/

# install glowroot
ENV GLOWROOT_VERSION 0.8.6
RUN apt-get update \
  && apt-get -y install curl unzip \
  && curl -L https://github.com/glowroot/glowroot/releases/download/v$GLOWROOT_VERSION/glowroot-$GLOWROOT_VERSION-dist.zip > glowroot-dist.zip \
  && unzip glowroot-dist.zip -d /usr/share/tomcat \
  && rm glowroot-dist.zip \
  && apt-get -y purge --auto-remove curl unzip \
  && rm -r /var/lib/apt/lists/*

EXPOSE 8080
EXPOSE 3306
EXPOSE 4000

ENV CATALINA_OPTS \
  -Xms1g \
  -Xmx1g \
  -XX:+UseG1GC \
  -javaagent:/usr/share/tomcat/glowroot/glowroot.jar \
  -Djava.security.egd=file:/dev/urandom \
  $HEATCLINIC_OPTS

CMD /etc/init.d/mysql start && /usr/share/tomcat/bin/catalina.sh run
