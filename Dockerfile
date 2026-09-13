FROM quay.io/centos/centos:stream10

USER root
# 1. Global fix for SSL/Randomness errors
RUN sed -i 's/https:/http:/g' /etc/yum.repos.d/*.repo

# 2. Install EPEL and all build dependencies
# Note: python3-config is part of python3-devel, so it's removed from the list
RUN yum install -y epel-release && \
    sed -i 's/https:/http:/g' /etc/yum.repos.d/*.repo && \
    yum install -y \
        git \
        make \
        gcc \
        gcc-c++ \
        clang \
        clang-tools-extra \
        cmake \
        gdb \
        nodejs \
        npm \
        fzf \
        ncurses-devel \
        python3-devel \
        ripgrep \
        curl \
        libasan \
        libtsan \
        libubsan \
        valgrind && \
    yum clean all && \
    ldconfig && \
    GCC_LIB=$(find /usr/lib/gcc -path '*/libubsan.so' | head -n 1) && \
    if [ -n "$GCC_LIB" ]; then \
        mkdir -p /usr/lib64 && \
        rm -f /usr/lib64/libubsan.so.1.0.0 /usr/lib64/libubsan.so.1 /usr/lib64/libubsan.so && \
        ln -s "$GCC_LIB" /usr/lib64/libubsan.so.1.0.0 && \
        ln -s "$GCC_LIB" /usr/lib64/libubsan.so.1 && \
        ln -s "$GCC_LIB" /usr/lib64/libubsan.so; \
    fi

# --- NEW: systemd, so this image behaves like a real RHEL host for the Linux course ---
# The base image is minimal and ships without an init system. Installing systemd here
# and running it as PID 1 (see ENTRYPOINT below) is what makes hostnamectl, systemctl,
# and journalctl actually work instead of failing with "not booted with systemd".
RUN yum install -y systemd systemd-udev && yum clean all

# A handful of systemd units assume access to real hardware or a full boot sequence
# that doesn't exist inside a container. Masking them avoids boot hangs/noise; nothing
# in this course exercises them anyway.
RUN systemctl mask \
        systemd-remount-fs.service \
        systemd-udevd.service \
        systemd-udevd-control.socket \
        systemd-udevd-kernel.socket \
        systemd-udev-trigger.service \
        systemd-machine-id-commit.service \
        dev-hugepages.mount \
        sys-kernel-config.mount \
        sys-kernel-debug.mount \
        sys-kernel-tracing.mount \
        getty.target \
        console-getty.service

# systemd expects this signal (not the default SIGTERM) to shut down cleanly
STOPSIGNAL SIGRTMIN+3


# 3. Build Vim
RUN git config --global http.sslVerify false && \
    cd /tmp && \
    git clone --depth 1 https://github.com/vim/vim.git && \
    cd vim && \
    ./configure --with-features=huge \
                --enable-multibyte \
                --enable-python3interp=yes \
                --with-python3-config-dir=$(python3-config --configdir) \
                --prefix=/usr/local && \
    make -j$(nproc) && \
    make install && \
    cd / && \
    rm -rf /tmp/vim


# 5. Install vim-plug
RUN curl -fLo /root/.vim/autoload/plug.vim --create-dirs --insecure \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# 6. Setup Configuration Files
COPY .vimrc /root/.vimrc
RUN mkdir -p /root/.vim
COPY coc-settings.json /root/.vim/coc-settings.json
# Ensure these exist or remove if not present in your build context
COPY .clangd /root/.clangd 
COPY quick-reference.txt /root/quick-reference.txt

# 7. Install Vim plugins (ignore errors to prevent build break)
RUN vim -E -s -u "/root/.vimrc" +PlugInstall +qall || true

# 8. Install coc extensions
RUN mkdir -p /root/.config/coc/extensions && \
    cd /root/.config/coc/extensions && \
    echo '{"dependencies":{}}' > package.json && \
    npm config set strict-ssl false && \
    npm config set registry http://registry.npmjs.org/ && \
    npm install coc-clangd coc-json --global-style --ignore-scripts --no-bin-links --no-package-lock

# 9. Verify and Bash Setup
RUN echo 'cat ~/quick-reference.txt 2>/dev/null || true' >> /root/.bashrc

# --- CHANGED: PID 1 must be systemd (init), not vim or bash, for the course to work.
# Get an interactive shell afterward with: docker exec -it <container> bash
ENTRYPOINT ["/usr/sbin/init"]
