# Simple SSH Server

This is simple SSH server image with *rsync* installed, built on the latest **Alpine Edge** image. It's configured to be used with **public key only** root login.

I've create this image to allow file transfers using **rsync through SSH** to a volume inside my Kubernetes Cluster. 

Since i'm using *Rancher's Longhorn* volumes created by it's UI, I just have to mount the PVC into a single pod, then use a **Load Balancer** service (If you have a external loadbalancer or a internal loadbalancer service, like MetalLB or KlipperLB) or a **Headless** service *(ClusterIP: None)* with a **TCP Ingress Controller** like *Traefik* or *Nginx*.

You can use one of my guides bellow:

# Pod with Headless Service and Traefik 2.X CRDs
- Before starting this guide, you must have the **SSH public key for the private key** you want to use to connect to the SSH server.

- Create a **ConfigMap** to store your SSH public key:
  ```
  kubectl create configmap ssh-auth-key -n mynamespace --from-file=authorized_keys=~/.ssh/mykey.pub
  ```

- Create a **Headless** service manifest with a *selector* and a *port mapping* to the ssh port:
  ```yaml
  apiVersion: v1
  kind: Service
  metadata:
    name: ssh-server
    namespace: mynamespace
  spec:
    type: ClusterIP
    clusterIP: None
    selector:
      name: ssh-server
    ports:
    - name: ssh
      port: 22
      protocol: TCP
      targetPort: 22
  ```
  ```
  kubectl apply -f service-ssh-server.yaml
  ```

- Create a **Pod** manifest with the *ConfigMap* and the *PVC* mounts:
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    name: ssh-server
    namespace: mynamespace
    labels:
      name: ssh-server
  spec:
    containers:
      - name: ssh-server
        image: masteredward/simple-ssh-server
        ports:
          - containerPort: 22
            name: ssh
            protocol: TCP
        volumeMounts:
          - name: authorized-keys
            mountPath: /root/.ssh/authorized_keys
            subPath: authorized_keys
          - name: mypvc
            mountPath: /mnt
    volumes:
      - name: authorized-keys
        configMap:
          name: ssh-auth-key
      - name: mypvc
        persistentVolumeClaim:
          claimName: my-longhorn-pvc
  ```
  ```
  kubectl apply -f pod-ssh-server.yaml
  ```

- Create a **Traefik 2.X IngressRouteTCP CRD** manifest to route an external entrypoint to the **Headless Service**. Traefik must have an entrypoint configured with the chosen port bound to it's containers. (In this example, the port is 2222 and the entrypoint name is **tcp2222**):
  ```yaml
  apiVersion: traefik.containo.us/v1alpha1
  kind: IngressRouteTCP
  metadata:
    name: ssh-server
    namespace: traefik
  spec:
    entryPoints:
      - tcp2222
    routes:
      - match: "HostSNI(`*`)"
        services:
          - name: ssh-server
            namespace: mynamespace
            port: 22
  ```
  ```
  kubectl apply -f irtcp-ssh-server.yaml
  ```

- Traefik Configuration Examples:
  ```yaml
  # ConfigMap
  
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: traefik-config
    namespace: traefik
  data:
    traefik.yaml: |-
      providers:
        kubernetesCRD: {}
        kubernetesIngress: {}
        file:
          filename: /etc/traefik/traefik.yaml
          watch: true
      entryPoints:
        web:
          address: ":80"
        websecure:
          address: ":443"
        tcp2222:
          address: ":2222"
  ```
  ```yaml
  # DaemonSet

  apiVersion: apps/v1
  kind: DaemonSet
  metadata:
    name: traefik-ingress-controller
    namespace: traefik
  spec:
    selector:
      matchLabels:
        name: traefik-ingress-controller
    template:
      metadata:
        labels:
          name: traefik-ingress-controller
      spec:
        serviceAccountName: traefik-ingress-controller
        containers:
        - name: traefik-ingress-controller
          image: traefik:2.3
          ports:
          - containerPort: 80
            hostPort: 80
            name: http
            protocol: TCP
          - containerPort: 443
            hostPort: 443
            name: https
            protocol: TCP
          - containerPort: 2222
            hostPort: 2222
            name: tcp2222
            protocol: TCP
          volumeMounts:
          - name: config
            mountPath: /etc/traefik/traefik.yaml
            subPath: traefik.yaml
            readOnly: true
        volumes:
        - name: config
          configMap:
            name: traefik-config
  ```
