destprefix=/opt/docker/debug
kubectl -n $1 exec $2 -- /bin/bash -xc " mkdir -p $destprefix/apt $destprefix/dpkg; \
  touch $destprefix/dpkg/status; \
  cd $destprefix; \
  apt-get -o Dir::Cache=$destprefix/apt -o Dir::State=$destprefix/apt update; \
  apt-get -o Dir::Cache=$destprefix/apt/ -o Dir::State=$destprefix/apt/ download openjdk-11-jdk-headless openjdk-11-jre-headless procps curl libprocps8 libcurl4 && \
  find $destprefix -name '*.deb' -exec dpkg-deb -x {} $destprefix \; ; \
  echo 'export LD_LIBRARY_PATH=\$HOME/debug/lib/x86_64-linux-gnu:\$HOME/debug/usr/lib/x86_64-linux-gnu' >> ~/.bashrc ; \
  echo 'PATH=\$HOME/debug/bin:\$HOME/debug/usr/bin:\$HOME/debug/usr/lib/jvm/java-11-openjdk-amd64/bin:\$PATH' >> ~/.bashrc"

kubectl -n $1 exec -ti $2 -- /bin/bash

