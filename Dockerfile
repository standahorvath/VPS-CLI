FROM ubuntu:22.04

# Základní nástroje
RUN apt-get update && \
    apt-get install -y \
        bash \
        curl \
        nano \
        git \
        sudo && \
    apt-get clean

# Výchozí pracovní adresář
WORKDIR /root

# Volitelné: automatické spuštění po vstupu
CMD ["bash"]
