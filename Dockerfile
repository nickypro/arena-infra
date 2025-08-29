# Base image from RunPod
FROM runpod/pytorch:2.4.0-py3.11-cuda12.4.1-devel-ubuntu22.04

ARG ARENA_REPO_ARG="callummcdougall/ARENA_3.0"
ARG DOTFILES_REPO_ARG="nickypro/arena-infra" # For reference

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/conda/bin:${PATH}"
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# Set shell for RUN commands to enable sourcing and robust error handling
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy the main script over first to set up packages
COPY ./scripts/docker_setup.sh /usr/local/bin/docker_setup.sh
RUN chmod +x /usr/local/bin/docker_setup.sh
RUN /usr/local/bin/docker_setup.sh "${ARENA_REPO_ARG}"

# Copy the rest of the repo to set up ZSH
RUN mkdir -p /root/.arena_infra
COPY ./scripts /root/.arena_infra/scripts
COPY ./dotfiles /root/.arena_infra/dotfiles
RUN chmod +x /root/.arena_infra/scripts/zsh_setup.sh
RUN chmod +x /root/.arena_infra/scripts/motd.sh
RUN /root/.arena_infra/scripts/zsh_setup.sh

# Clean up APT cache to reduce image size
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set the default working directory for the container
WORKDIR /workspace

# Default command when container starts (same as base RunPod image)
CMD ["/start.sh"]
