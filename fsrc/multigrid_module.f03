module multigrid_module

    use tridag_module, only: tridag
    use scala3
    use period
    use mysending
    use mysettings, only: freesurface,bodyforce
    !
    use mpi

    use iso_c_binding

    integer(kind=c_int),bind(C),public :: islor
    integer(kind=c_int),bind(C),public :: nlevmultimax
    real(kind=c_double),bind(C),public :: omega

    private

    ! array for controvariant metric tensor for multigrid level 1,2,3,4
    integer,allocatable,public :: in_dx1(:,:,:),in_sn1(:,:,:),in_sp1(:,:,:),in_st1(:,:,:),in_av1(:,:,:),in_in1(:,:,:)
    integer,allocatable :: in_dx2(:,:,:),in_sn2(:,:,:),in_sp2(:,:,:),in_st2(:,:,:),in_av2(:,:,:),in_in2(:,:,:)
    integer,allocatable :: in_dx3(:,:,:),in_sn3(:,:,:),in_sp3(:,:,:),in_st3(:,:,:),in_av3(:,:,:),in_in3(:,:,:)
    integer,allocatable :: in_dx4(:,:,:),in_sn4(:,:,:),in_sp4(:,:,:),in_st4(:,:,:),in_av4(:,:,:),in_in4(:,:,:)

    real,allocatable :: g11_2(:,:,:),g12_2(:,:,:),g13_2(:,:,:)
    real,allocatable :: g21_2(:,:,:),g22_2(:,:,:),g23_2(:,:,:)
    real,allocatable :: g31_2(:,:,:),g32_2(:,:,:),g33_2(:,:,:)
    real,allocatable :: g11_3(:,:,:),g12_3(:,:,:),g13_3(:,:,:)
    real,allocatable :: g21_3(:,:,:),g22_3(:,:,:),g23_3(:,:,:)
    real,allocatable :: g31_3(:,:,:),g32_3(:,:,:),g33_3(:,:,:)
    real,allocatable :: g11_4(:,:,:),g12_4(:,:,:),g13_4(:,:,:)
    real,allocatable :: g21_4(:,:,:),g22_4(:,:,:),g23_4(:,:,:)
    real,allocatable :: g31_4(:,:,:),g32_4(:,:,:),g33_4(:,:,:)
      
    real,allocatable :: den_1(:,:,:),den_2(:,:,:),den_3(:,:,:),den_4(:,:,:)

    ! coefficent for tridiagonal system (see sett.f)
    ! for each level implicit solution in eta
    real,allocatable :: aa1(:,:,:),bb1(:,:,:),cc1(:,:,:)
    real,allocatable :: aa2(:,:,:),bb2(:,:,:),cc2(:,:,:)
    real,allocatable :: aa3(:,:,:),bb3(:,:,:),cc3(:,:,:)
    real,allocatable :: aa4(:,:,:),bb4(:,:,:),cc4(:,:,:)

    public :: multi,mul_met,wall

    ! these where in strati (the main)
    integer,public :: kpstamg(0:4),kpendmg(0:4),kfacepstamg(0:4)
    integer,public :: ncolprocmg(0:4)

contains

    subroutine multi(eps,ficycle,nlevel,jxc,jyc,jzc,tipo,iterat)

        ! pressure solution with sor+multigrid
        !
        use myarrays_metri3
        use myarrays_velo3
        !
        implicit none

        !-----------------------------------------------------------------------
        !     array declaration
        integer kstamg(4),kendmg(4),ncolprocmg(4)
        integer n12,n22,n32,n13,n23,n33,n14,n24,n34
        !
        integer i,j,k,nlevel,n,ktime
        integer jxc(0:4),jyc(0:4),jzc(0:4)
        integer kss(4)
        !
        real aresi,eps,resmax
        real resmax_loc
        real,allocatable :: rhsn(:,:,:) !n3)
        real,allocatable :: rhs2v(:,:,:) !n32)
        real,allocatable :: rhs2n(:,:,:) !n32)
        real,allocatable :: rhs3v(:,:,:) !n33)
        real,allocatable :: rhs3n(:,:,:) !n33)
        real,allocatable :: rhs4v(:,:,:) !n34)
        !
        real,allocatable :: pr1(:,:,:)
        real,allocatable :: pr2(:,:,:) !0:n32+1)
        real,allocatable :: pr3(:,:,:) !0:n33+1)
        real,allocatable :: pr4(:,:,:) !0:n34+1)

        !
        integer ierr
        integer ficycle
        !
        integer iterat

        !
        !     for potential flow with ibm
        integer tipo(0:n1+1,0:n2+1,kparasta-deepl:kparaend+deepr)
        integer itipo,finetipo
        !-----------------------------------------------------------------------
        !
        ! matrix initialization
        !
        n12=n1/2
        n22=n2/2
        n32=n3/2
        n13=n1/4
        n23=n2/4
        n33=n3/4
        n14=n1/8
        n24=n2/8
        n34=n3/8
        !
        ! put pressure on support matrix pr1
        !
        nlevel=nlevmultimax
        !
        !     nlevel=1 is the first multigrid level
        !
        if (myid==0) then
            !write(*,*) 'nlevmultimax=',nlevmultimax
            do n=1,nlevel
                !write(*,*) 'level=',n,myid,jxc(n),jyc(n),jzc(n)
            end do
        end if

        ! AAA chicco: mettere meglio la allocazione nel caso si riducano i livelli
        ! di multigrid, oppure non siano garantiti tutti i livelli

        kstamg = 0
        kendmg = 0

        do n=1,nlevel
            ncolprocmg(n)=jzc(n)/nproc
            kstamg(n)=(myid*ncolprocmg(n)+1)
            kendmg(n)=((myid+1)*ncolprocmg(n))
        end do

        allocate( rhsn(n1 ,n2 ,kstamg(1):kendmg(1))) !n3)
        allocate(rhs2v(n12,n22,kstamg(2):kendmg(2))) !n32)
        allocate(rhs2n(n12,n22,kstamg(2):kendmg(2))) !n32)
        allocate(rhs3v(n13,n23,kstamg(3):kendmg(3))) !n33)
        allocate(rhs3n(n13,n23,kstamg(3):kendmg(3))) !n33)
        allocate(rhs4v(n14,n24,kstamg(4):kendmg(4))) !n34)
        !
        allocate(pr1(0:n1 +1,0:n2 +1,kstamg(1)-1:kendmg(1)+1))
        allocate(pr2(0:n12+1,0:n22+1,kstamg(2)-1:kendmg(2)+1)) !0:n32+1)
        allocate(pr3(0:n13+1,0:n23+1,kstamg(3)-1:kendmg(3)+1)) !0:n33+1)
        allocate(pr4(0:n14+1,0:n24+1,kstamg(4)-1:kendmg(4)+1)) !0:n34+1)

        call mul_ini(n1,n2,n12,n13,n14,n22,n23,n24,rhsn,rhs2v,rhs3v,rhs4v,pr2,pr3,pr4,kstamg,kendmg)

        !
        ! sor iteration for each level
        !
        do n=1,nlevel
            kss(n)=5
            if (n>1) kss(n)=10
        end do
        !
        !------------------------------------------------------------------------
        ! initialization
        !
        ktime=0
        resmax=1.
        !
        do while (ktime<ficycle .and. resmax>=eps)

            ktime=ktime+1

            if (nlevel>=1) then
                do k=kstamg(1)-1,kendmg(1)+1 !kparasta,kparaend
                    do j=0,n2+1
                        do i=0,n1+1
                            pr1(i,j,k)=fi(i,j,k)
                        end do
                    end do
                end do
            end if
            if (nlevel>=2) then
                do k=kstamg(2)-1,kendmg(2)+1 !0,jzc(2)+1
                    do j=0,jyc(2)+1
                        do i=0,jxc(2)+1
                            pr2(i,j,k)=0.0
                        end do
                    end do
                end do
            end if
            if (nlevel>=3) then
                do k=kstamg(3)-1,kendmg(3)+1 !0,jzc(3)+1
                    do j=0,jyc(3)+1
                        do i=0,jxc(3)+1
                            pr3(i,j,k)=0.0
                        end do
                    end do
                end do
            end if
            if (nlevel>=4) then
                do k=kstamg(4)-1,kendmg(4)+1 !0,jzc(4)+1
                    do j=0,jyc(4)+1
                        do i=0,jxc(4)+1
                            pr4(i,j,k)=0.0
                        end do
                    end do
                end do
            end if
            !
            !
            !     start computation on levels from fine to coarse

            do n=1,nlevel

                !
                !
                !-----------------------------------------------------------------------
                if (n==1) then        ! first grid
                    !-----------------------------------------------------------------------

                    if (islor==0) then

                        call solut_sndrcv_sor(n,n1,n2,kss,jxc,jyc,jzc,pr1,rhs, &
                            g11,g12,g13,g21,g22,g23,g31,g32,g33,kstamg,kendmg,iterat)


                        if (bodyforce) then ! .and. bodypressure
                                call potenziale_ibm(tipo)
                        end if



                    else if (islor==1) then
                        call solut_sndrcv_slor(n,n1,n2,kss,jxc,jyc,jzc,pr1,rhs, &
                            cs1,cs2,cs3,cs4,cs5,cs6,g11,g12,g13,g21,g22,g23,g31,g32,g33, &
                            in_dx1,in_sn1,in_av1,in_in1,kstamg,kendmg,aa1,bb1,cc1)

                    end if

                    call resid_sndrcv(n,n1,n2,jxc,jyc,pr1,rhsn,rhs,g11,g22,g33,kstamg,kendmg)

                    if (nlevel/=1) then
                        call restrict_sndrcv(n,n1,n2,n12,n22,jxc,jyc,rhsn,rhs2v,kstamg,kendmg)
                    end if

                !-----------------------------------------------------------------------
                else if (n==2) then           !second grid
                    !-----------------------------------------------------------------------
                    !
                    if (islor==0) then
                        call solut_sndrcv_sor(n,n12,n22,kss,jxc,jyc,jzc,pr2,rhs2v, &
                            g11_2,g12_2,g13_2,g21_2,g22_2,g23_2,g31_2,g32_2,g33_2, &
                            kstamg,kendmg,iterat)
                    else if (islor==1) then

                        call solut_sndrcv_slor(n,n12,n22,kss,jxc,jyc,jzc,pr2,rhs2v, &
                            cs1,cs2,cs3,cs4,cs5,cs6, &
                            g11_2,g12_2,g13_2,g21_2,g22_2,g23_2,g31_2,g32_2,g33_2, &
                            in_dx2,in_sn2,in_av2,in_in2,kstamg,kendmg,aa2,bb2,cc2)
                    end if
                    !
                    if (n<nlevel) then

                        call resid_sndrcv(n,n12,n22,jxc,jyc,pr2,rhs2n,rhs2v,g11_2,g22_2,g33_2,kstamg,kendmg)

                        call restrict_sndrcv(n,n12,n22,n13,n23,jxc,jyc,rhs2n,rhs3v,kstamg,kendmg)
                    !
                    end if
                !
                !
                !-----------------------------------------------------------------------
                else if (n==3) then           !third grid
                    !-----------------------------------------------------------------------
                    !
                    !
                    if (islor==0) then
                        call solut_sndrcv_sor(n,n13,n23,kss,jxc,jyc,jzc,pr3,rhs3v, &
                            g11_3,g12_3,g13_3,g21_3,g22_3,g23_3,g31_3,g32_3,g33_3, &
                            kstamg,kendmg,iterat)
                    else if (islor==1) then

                        call solut_sndrcv_slor(n,n13,n23,kss,jxc,jyc,jzc,pr3,rhs3v, &
                            cs1,cs2,cs3,cs4,cs5,cs6, &
                            g11_3,g12_3,g13_3,g21_3,g22_3,g23_3,g31_3,g32_3,g33_3, &
                            in_dx3,in_sn3,in_av3,in_in3,kstamg,kendmg,aa3,bb3,cc3)
                    end if
                    !
                    if (n<nlevel) then

                        call resid_sndrcv(n,n13,n23,jxc,jyc,pr3,rhs3n,rhs3v,g11_3,g22_3,g33_3,kstamg,kendmg)
                        !
                        call restrict_sndrcv(n,n13,n23,n14,n24,jxc,jyc,rhs3n,rhs4v,kstamg,kendmg)
                    !
                    end if
                !
                !
                !-----------------------------------------------------------------------
                else if (n==4) then           !fourth grid
                    !-----------------------------------------------------------------------
                    !
                    if (islor==0) then
                        call solut_sndrcv_sor(n,n14,n24,kss,jxc,jyc,jzc,pr4,rhs4v, &
                            g11_4,g12_4,g13_4,g21_4,g22_4,g23_4,g31_4,g32_4,g33_4, &
                            kstamg,kendmg,iterat)

                    else if (islor==1) then

                        call solut_sndrcv_slor(n,n14,n24,kss,jxc,jyc,jzc,pr4,rhs4v, &
                            cs1,cs2,cs3,cs4,cs5,cs6, &
                            g11_4,g12_4,g13_4,g21_4,g22_4,g23_4,g31_4,g32_4,g33_4, &
                            in_dx4,in_sn4,in_av4,in_in4,kstamg,kendmg,aa4,bb4,cc4)
                    end if
                !
                end if
            !

            end do

            !-----------------------------------------------------------------------
            !-------------- start cycle from coarse to fine ------------------------
            !-----------------------------------------------------------------------
            !
            do n=nlevel-1,1,-1
                !
                !-----------------------------------------------------------------------
                if (n==3)      then           !third grid
                    !-----------------------------------------------------------------------
                    !
                    call prolong(n,n13,n23,n14,n24,jxc,jyc,pr3,pr4,kstamg,kendmg)
                    !
                    if (islor==0) then
                        call solut_sndrcv_sor(n,n13,n23,kss,jxc,jyc,jzc,pr3,rhs3v, &
                            g11_3,g12_3,g13_3,g21_3,g22_3,g23_3,g31_3,g32_3,g33_3, &
                            kstamg,kendmg,iterat)
                    else if (islor==1) then

                        call solut_sndrcv_slor(n,n13,n23,kss,jxc,jyc,jzc,pr3,rhs3v, &
                            cs1,cs2,cs3,cs4,cs5,cs6,g11_3,g12_3,g13_3, &
                            g21_3,g22_3,g23_3,g31_3,g32_3,g33_3, &
                            in_dx3,in_sn3,in_av3,in_in3,kstamg,kendmg,aa3,bb3,cc3)
                    end if
                !
                !-----------------------------------------------------------------------
                else if (n==2) then           !second grid
                    !-----------------------------------------------------------------------
                    !
                    call prolong(n,n12,n22,n13,n23,jxc,jyc,pr2,pr3,kstamg,kendmg)
                    !
                    if (islor==0) then
                        call solut_sndrcv_sor(n,n12,n22,kss,jxc,jyc,jzc,pr2,rhs2v, &
                            g11_2,g12_2,g13_2,g21_2,g22_2,g23_2,g31_2,g32_2,g33_2, &
                            kstamg,kendmg,iterat)
                    else if (islor==1) then

                        call solut_sndrcv_slor(n,n12,n22,kss,jxc,jyc,jzc,pr2,rhs2v, &
                            cs1,cs2,cs3,cs4,cs5,cs6, &
                            g11_2,g12_2,g13_2,g21_2,g22_2,g23_2,g31_2,g32_2,g33_2, &
                            in_dx2,in_sn2,in_av2,in_in2,kstamg,kendmg,aa2,bb2,cc2)
                    end if
                !
                !-----------------------------------------------------------------------
                else if (n==1) then           !first grid
                    !-----------------------------------------------------------------------
                    !
                    call prolong(n,n1,n2,n12,n22,jxc,jyc,pr1,pr2,kstamg,kendmg)
                    !
                    if (islor==0) then

                        if (bodyforce) then ! .and. bodypressure
                                call potenziale_ibm(tipo)
                        end if

                        call solut_sndrcv_sor(n,n1,n2,kss,jxc,jyc,jzc,pr1,rhs, &
                            g11,g12,g13,g21,g22,g23,g31,g32,g33,kstamg,kendmg,iterat)

                        if (bodyforce) then ! .and. bodypressure
                                call potenziale_ibm(tipo)
                        end if

                    else if (islor==1) then

                        call solut_sndrcv_slor(n,n1,n2,kss,jxc,jyc,jzc,pr1,rhs, &
                            cs1,cs2,cs3,cs4,cs5,cs6,g11,g12,g13,g21,g22,g23,g31,g32,g33, &
                            in_dx1,in_sn1,in_av1,in_in1,kstamg,kendmg,aa1,bb1,cc1)
                    end if
                !
                end if
            !
            end do
            !-----------------------------------------------------------------------
            ! compute residual on first level grid
            !
            n=1

            if (nlevel>1) then

                call resid_sndrcv(n,n1,n2,jxc,jyc, &
                    pr1,rhsn,rhs,g11,g22,g33,kstamg,kendmg)

            end if
            !-----------------------------------------------------------------------

            do k=kstamg(n)-1,kendmg(n)+1 !kparasta,kparaend
                do j=0,n2+1
                    do i=0,n1+1
                        fi(i,j,k)=pr1(i,j,k)
                    end do
                end do
            end do


            ! compute resmax
            !
            !     without IBM
            if (.not.bodyforce) then
                resmax_loc=0.
                do k=kstamg(n),kendmg(n)
                    do j=1,jyc(n)
                        do i=1,jxc(n)
                            !
                            aresi=abs(rhsn(i,j,k))
                            resmax_loc=max(resmax_loc,aresi)
                        !
                        end do
                    end do
                end do
            end if

            !     with IBM
            if (bodyforce) then
                resmax_loc=0.
                do k=kstamg(n),kendmg(n)
                    do j=1,jyc(n)
                        do i=1,jxc(n)
                            !
                            finetipo = tipo(i,j,k)
                            do itipo=2,finetipo
                                aresi=abs(rhsn(i,j,k))
                                resmax_loc=max(resmax_loc,aresi)
                            end do
                        !
                        end do
                    end do
                end do
            end if
            !
            call MPI_ALLREDUCE(resmax_loc,resmax,1,MPI_REAL_SD,MPI_MAX,MPI_COMM_WORLD,ierr)
            call MPI_BARRIER(MPI_COMM_WORLD,ierr)

            if (myid==0) then
                write(*,*)myid,' ','ktime, resmax',ktime,resmax
            end if

        end do
        !
        deallocate( rhsn) !n3)
        deallocate(rhs2v) !n32)
        deallocate(rhs2n) !n32)
        deallocate(rhs3v) !n33)
        deallocate(rhs3n) !n33)
        deallocate(rhs4v) !n34)
        !
        deallocate(pr1)
        deallocate(pr2) !0:n32+1)
        deallocate(pr3) !0:n33+1)
        deallocate(pr4) !0:n34+1)

        !-----------------------------------------------------------------------
        return
    end subroutine multi

    subroutine solut_sndrcv_sor(n,i1,j1,kss,jxc,jyc,jzc,pr,rh, &
        r11,r12,r13,r21,r22,r23,r31,r32,r33,kstamg,kendmg,iterat)

        ! smoothing on every level with SOR

        implicit none

        !-----------------------------------------------------------------------
        !     array declaration
        integer kstamg(4),kendmg(4)
        integer i,j,k,ipot,i1,j1,n,kk
        integer kss(4)
        integer jxc(0:4),jyc(0:4),jzc(0:4)
        !
        integer ierr,status(MPI_STATUS_SIZE)
        integer prplan
        integer iii,jjj,kkk
        !
        real pot,ppot1,ppot2,resi,den
        real sq_ppot1
        real res_av,res_ind,res_sot,res_sop,res_sn,res_dx
        real den_av,den_ind,den_sot,den_sop,den_sn,den_dx

        real r11(0:i1,  j1,  kstamg(n):kendmg(n))
        real r12(0:i1,  j1,  kstamg(n):kendmg(n))
        real r13(0:i1,  j1,  kstamg(n):kendmg(n))
        real r21(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r22(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r23(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r31(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r32(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r33(i1  ,  j1,kstamg(n)-1:kendmg(n))

        real pr(0:i1+1,0:j1+1,kstamg(n)-1:kendmg(n)+1)
        real rh(i1,j1,kstamg(n):kendmg(n))
        !
        !      integer tipo(0:n1+1,0:n2+1,kparasta-1:kparaend+1)
        integer iterat

        !     define the new data type MPI to exchange pressure points
        call MPI_TYPE_VECTOR(jyc(n),jxc(n),jxc(n)+2,MPI_REAL_SD,prplan,ierr)
        call MPI_TYPE_COMMIT(prplan,ierr)
        !-----------------------------------------------------------------------

        ipot=2**(n-1)
        pot=float(ipot)
        ppot1=1/pot
        sq_ppot1 = ppot1*ppot1
        ppot2=1/pot/pot

        do kk=1,kss(n)

            !
            !     boundary condition
            call mul_boun_sndrcv(n,i1,j1,jxc,jyc,jzc, &
                r11,r12,r13,r21,r22,r23,r31,r32,r33,pr,kstamg,kendmg,iterat)

            ! smoothing with SOR
            ! on vertical plane zebra! odd and even

            !hicco togliere lo zebra
            !      do kcs=1,2
            !      n1k=mod(kcs,4)

            !      do jcs=1,2
            !      n1j=mod(jcs,4)

            !      do ics=1,2
            !      n1i=mod(ics,4)
            !
            ! exchange boundary values for k=0 and k=jzc(n)
            do kkk=1,1-kp

                !c      if (kcs==1) then

                if (myid==nproc-1) then
                    call MPI_SEND(pr(1,1,jzc(n)),1,prplan,0,11,MPI_COMM_WORLD,ierr)
                else if (myid==0) then
                    call MPI_RECV(pr(1,1,0),1,prplan,nproc-1,11,MPI_COMM_WORLD,status,ierr)
                end if

                !c      else if (kcs==2) then

                if (myid==0) then
                    call MPI_SEND(pr(1,1,1),1,prplan,nproc-1,12,MPI_COMM_WORLD,ierr)
                else if (myid==nproc-1) then
                    call MPI_RECV(pr(1,1,jzc(n)+1),1,prplan,0,12,MPI_COMM_WORLD,status,ierr)
                end if

            !c      end if

            end do


            do k=kstamg(n),kendmg(n)
                !      do k=(n1k-1)+kstamg(n),kendmg(n),2
                !
                do j=1,jyc(n)
                    !      do j=n1j,jyc(n),2
                    !
                    do iii=1,1-ip

                        pr(0,j,k)=pr(jxc(n),j,k)
                        pr(jxc(n)+1,j,k)=pr(1,j,k)

                    end do
                    !
                    do i=1,jxc(n)
                        !      do i=n1i,jxc(n),2

                        ! direction j is always not periodic

                        !
                        !      right residual
                        res_dx=( &
                            r11(i,j,k)*(pr(i+1,j,k)-pr(i,j,k))+ &
                            .25*(r12(i,j,k)* &
                            (pr(i+1,j+1,k)+pr(i,j+1,k)-pr(i+1,j-1,k)-pr(i,j-1,k)) &
                            +r13(i,j,k)* &
                            (pr(i+1,j,k+1)+pr(i,j,k+1)-pr(i+1,j,k-1)-pr(i,j,k-1))) &
                            )*ppot1
                        !
                        den_dx=r11(i,j,k)*ppot2
                        !
                        !      left residual
                        res_sn=( &
                            r11(i-1,j,k)*(pr(i,j,k)-pr(i-1,j,k))+ &
                            .25*(r12(i-1,j,k)* &
                            (pr(i,j+1,k)+pr(i-1,j+1,k)-pr(i,j-1,k)-pr(i-1,j-1,k)) &
                            +r13(i-1,j,k)* &
                            (pr(i,j,k+1)+pr(i-1,j,k+1)-pr(i,j,k-1)-pr(i-1,j,k-1))) &
                            )*ppot1
                        !
                        den_sn=r11(i-1,j,k)*ppot2
                        !
                        !      upper residual
                        res_sop=( &
                            r22(i,j,k)*(pr(i,j+1,k)-pr(i,j,k))+ &
                            .25*(r21(i,j,k)* &
                            (pr(i+1,j+1,k)+pr(i+1,j,k)-pr(i-1,j+1,k)-pr(i-1,j,k)) &
                            +r23(i,j,k)* &
                            (pr(i,j+1,k+1)+pr(i,j,k+1)-pr(i,j+1,k-1)-pr(i,j,k-1))) &
                            )*ppot1
                        !
                        den_sop=r22(i,j,k)*ppot2
                        !
                        !     bottom residual
                        res_sot=( &
                            r22(i,j-1,k)*(pr(i,j,k)-pr(i,j-1,k))+ &
                            .25*(r21(i,j-1,k)* &
                            (pr(i+1,j,k)+pr(i+1,j-1,k)-pr(i-1,j,k)-pr(i-1,j-1,k)) &
                            +r23(i,j-1,k)* &
                            (pr(i,j,k+1)+pr(i,j-1,k+1)-pr(i,j,k-1)-pr(i,j-1,k-1))) &
                            )*ppot1
                        !
                        den_sot=r22(i,j-1,k)*ppot2
                        !
                        !     front residual
                        res_av=( &
                            r33(i,j,k)*(pr(i,j,k+1)-pr(i,j,k))+ &
                            .25*(r31(i,j,k)* &
                            (pr(i+1,j,k+1)+pr(i+1,j,k)-pr(i-1,j,k+1)-pr(i-1,j,k)) &
                            +r32(i,j,k)* &
                            (pr(i,j+1,k+1)+pr(i,j+1,k)-pr(i,j-1,k+1)-pr(i,j-1,k))) &
                            )*ppot1
                        !
                        den_av=r33(i,j,k)*ppot2
                        !
                        !     back residual
                        res_ind=( &
                            r33(i,j,k-1)*(pr(i,j,k)-pr(i,j,k-1))+ &
                            .25*(r31(i,j,k-1)* &
                            (pr(i+1,j,k)+pr(i+1,j,k-1)-pr(i-1,j,k)-pr(i-1,j,k-1)) &
                            +r32(i,j,k-1)* &
                            (pr(i,j+1,k)+pr(i,j+1,k-1)-pr(i,j-1,k)-pr(i,j-1,k-1))) &
                            )*ppot1
                        !
                        den_ind=r33(i,j,k-1)*ppot2
                        !
                        resi= &
                            (res_dx  - res_sn  +  &
                            res_sop - res_sot + &
                            res_av  - res_ind )*ppot1 - rh(i,j,k)
                        !
                        den= den_dx + den_sn + den_sop + den_sot + den_av + den_ind
                        !

                        pr(i,j,k)=pr(i,j,k)+omega*resi/den
                    !


                    end do   ! done one complete sweep for 1 plane
                end do   ! done one complete sweep for 1 plane
            end do   ! done one complete sweep for odd or even lines
            !

            !      end do   ! done the 2 colors
            !      end do   ! done the 2 colors



            !c      if (kcs==1) then

            if (leftpem /= MPI_PROC_NULL) then
                call MPI_SEND(pr(1,1,kstamg(n)),1, &
                    prplan,leftpem,tagls, &
                    MPI_COMM_WORLD,ierr)
            end if
            if (rightpem /= MPI_PROC_NULL) then
                call MPI_RECV(pr(1,1,kendmg(n)+1),1, &
                    prplan,rightpem,tagrr, &
                    MPI_COMM_WORLD,status,ierr)
            end if

            !c      else if (kcs==2) then

            if (rightpem /= MPI_PROC_NULL) then
                call MPI_SEND(pr(1,1,kendmg(n)),1, &
                    prplan,rightpem,tagrs, &
                    MPI_COMM_WORLD,ierr)
            end if
            if (leftpem /= MPI_PROC_NULL) then
                call MPI_RECV(pr(1,1,kstamg(n)-1),1, &
                    prplan,leftpem,taglr, &
                    MPI_COMM_WORLD,status,ierr)
            end if

        !c      end if

        !      end do   ! done the 2 colors

        end do   ! end of a pseudo time iteration

        call MPI_TYPE_FREE(prplan,ierr)

        !     send ghost cell
        if (leftpem /= MPI_PROC_NULL) then
            call MPI_SEND(pr(0,0,kstamg(n)),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,leftpem,tagls, &
                MPI_COMM_WORLD,ierr)
        end if
        if (rightpem /= MPI_PROC_NULL) then
            call MPI_RECV(pr(0,0,kendmg(n)+1),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,rightpem,tagrr, &
                MPI_COMM_WORLD,status,ierr)
        end if
        if (rightpem /= MPI_PROC_NULL) then
            call MPI_SEND(pr(0,0,kendmg(n)),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,rightpem,tagrs, &
                MPI_COMM_WORLD,ierr)
        end if
        if (leftpem /= MPI_PROC_NULL) then
            call MPI_RECV(pr(0,0,kstamg(n)-1),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,leftpem,taglr, &
                MPI_COMM_WORLD,status,ierr)
        end if

        return

    end subroutine solut_sndrcv_sor

    subroutine mul_boun_sndrcv(n,i1,j1,jxc,jyc,jzc, &
        r11,r12,r13,r21,r22,r23,r31,r32,r33,pr, &
        kstamg,kendmg,iterat)
        !***********************************************************************
        ! update boundary condition for pressure with multigrid
        !
        use myarrays_velo3
        use myarrays_metri3

        implicit none

        !-----------------------------------------------------------------------
        !     array declaration
        integer i,j,k,ii,jj,kk,i1,j1,n,kkk
        integer jxc(0:4),jyc(0:4),jzc(0:4)
        !
        integer kstamg(4),kendmg(4)
        integer ierr,status(MPI_STATUS_SIZE)
        integer prplan
        integer iterat
        !
        real an
        real PrS0

        real r11(0:i1,  j1,  kstamg(n):kendmg(n))
        real r12(0:i1,  j1,  kstamg(n):kendmg(n))
        real r13(0:i1,  j1,  kstamg(n):kendmg(n))
        real r21(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r22(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r23(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r31(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r32(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r33(i1  ,  j1,kstamg(n)-1:kendmg(n))

        real pr(0:i1+1,0:j1+1,kstamg(n)-1:kendmg(n)+1)
        !      real cs1(n2,n3),cs2(n2,n3)
        !      real cs3(n1,n3),cs4(n1,n3)
        !      real cs5(n1,n2),cs6(n1,n2)
        !
        real,allocatable :: buffprs1(:)
        real,allocatable :: buffprs2(:)
        real,allocatable :: buffprr1(:)
        real,allocatable :: buffprr2(:)
        real,allocatable :: buff1s(:)
        real,allocatable :: buff2s(:)
        real,allocatable :: buff1r(:)
        real,allocatable :: buff2r(:)

        real inv_dt,coef
        real inv_r11,inv_r22,inv_r33
        real pi

        !-----------------------------------------------------------------------

        inv_dt = 1./dt
        coef = 0.25
        pi = acos(-1.)

        !     compute boundary condition for pressure
        if (n==1) then    ! first grid
            an=1.
        else                ! other grids
            an=0.
        end if
        !
        !
        do kkk=1,5 !loop su kkk
            !     compute pressure on ghost cell
            !-----------------------------------------------------------------------
            !     left and right
            do ii=1,ip
                do k=kstamg(n),kendmg(n)
                    do j=1,jyc(n)
                        !
                        inv_r11 = 1./r11(0,j,k)

                        pr(0,j,k)= pr(1,j,k) -an*cs1(j,k)*inv_dt*inv_r11 & !/dt/r11(0,j,k)
                            +coef*inv_r11   &
                            *(r12(0,j,k)* &
                            (pr(1,j+1,k)+pr(0,j+1,k)-pr(1,j-1,k)-pr(0,j-1,k)) &
                            +r13(0,j,k)* &
                            (pr(1,j,k+1)+pr(0,j,k+1)-pr(1,j,k-1)-pr(0,j,k-1)))
                        !     > + .25*r12(0,j,k)/r11(0,j,k)*
                        !     > (pr(1,j+1,k)+pr(0,j+1,k)-pr(1,j-1,k)-pr(0,j-1,k))+
                        !     >   .25*r13(0,j,k)/r11(0,j,k)*
                        !     > (pr(1,j,k+1)+pr(0,j,k+1)-pr(1,j,k-1)-pr(0,j,k-1))
                        !
                        inv_r11 = 1./r11(jxc(n),j,k)

                        pr(jxc(n)+1,j,k)= pr(jxc(n),j,k)+an*cs2(j,k)*inv_dt*inv_r11 & !/dt/r11(jxc(n),j,k)
                            -coef*inv_r11* &
                            (r12(jxc(n),j,k)* &
                            (pr(jxc(n)+1,j+1,k)+pr(jxc(n),j+1,k)- &
                            pr(jxc(n)+1,j-1,k)-pr(jxc(n),j-1,k)) &
                            +r13(jxc(n),j,k)* &
                            (pr(jxc(n)+1,j,k+1)+pr(jxc(n),j,k+1)- &
                            pr(jxc(n)+1,j,k-1)-pr(jxc(n),j,k-1)))
                    !
                    end do
                end do

            end do
            !
            !      periodic
            do ii=1,1-ip
                !
                do k=kstamg(n),kendmg(n)
                    do j=1,jyc(n)
                        !
                        pr(0       ,j,k)=pr(jxc(n),j,k)
                        pr(jxc(n)+1,j,k)=pr(1     ,j,k)
                    !
                    end do
                end do
            !
            end do
            !-----------------------------------------------------------------------
            !     bottom and upper
            ! direction j is always not periodic

                do k=kstamg(n),kendmg(n)
                    do i=1,jxc(n)
                        !
                        inv_r22 = 1./r22(i,0,k)

                        pr(i,0,k)=pr(i,1,k) -an*cs3(i,k)*inv_dt*inv_r22  & !/dt/r22(i,0,k)
                            +coef*inv_r22* &
                            (r21(i,0,k)* &
                            (pr(i+1,1,k)+pr(i+1,0,k)-pr(i-1,1,k)-pr(i-1,0,k)) &
                            +r23(i,0,k)* &
                            (pr(i,1,k+1)+pr(i,0,k+1)-pr(i,1,k-1)-pr(i,0,k-1)))
                        !
                        inv_r22 = 1./r22(i,jyc(n),k)

                        if (.not.freesurface) then !no free surface <<<<<<<<<<<<<<<
                            !    ORIGINAL code for the pressure at the surface:
                            pr(i,jyc(n)+1,k)=pr(i,jyc(n),k)+an*cs4(i,k)*inv_dt*inv_r22 & !/dt/r22(i,jyc(n),k)
                                -coef*inv_r22* &
                                (r21(i,jyc(n),k)* &
                                (pr(i+1,jyc(n)+1,k)+pr(i+1,jyc(n),k) &
                                -pr(i-1,jyc(n)+1,k)-pr(i-1,jyc(n),k)) &
                                +r23(i,jyc(n),k)* &
                                (pr(i,jyc(n)+1,k+1)+pr(i,jyc(n),k+1) &
                                -pr(i,jyc(n)+1,k-1)-pr(i,jyc(n),k-1)))
                        !
                        else if (freesurface) then !free surface on<<<<<<<<<<<<<<<<
                            !
                            !      the following if condition is to have an initial imposed surface pressure
                            PrS0=0.
                            if (iterat==1) then ! the initial surface pressure to be imposed HERE! <<<<<<<<<
                                !         PrS0 = ((16.5-i)/77.5)  !the value i want exactly at the surface
                                !         PrS0 = (9.81*0.02)*sin((i-1)*2*pi/31)  !the value i want exactly at the surface
                                !         wavel=20.
                                !         Kwavel=2.*pi/wavel
                                !         x_i=((10./32)*(i-1))+((10./32)*(1./2))
                                !         Tperiod=4.5
                                !         Wperiod=2.*pi/Tperiod
                                !         PrS0= 9.81*(0.02)*
                                !     >       (cos(Wperiod*ti) )*
                                !c                                     ! cos [ (2 * pi / T(period) ) * (time in seconds) ]
                                !c                                     ! T = 12hour * 3600(seconds in 1 hour)
                                !     >       (cos(Kwavel*x_i) )
                                !c                                     ! sin [ (2 * pi / wavelength) * (x function of i) ]
                                !c                                     ! wavelength = Lx
                                !
                                PrS0=0.
                            else ! the pressure at surface is imposed at iteration>1
                                if (n==1) then
                                    PrS0=next_prs(i,k)
                                end if
                            end if ! to have an initial imposed surface pressure
                            !
                            pr(i,jyc(n)+1,k)=(PrS0*2)-(pr(i,jyc(n),k) &
                                -coef*inv_r22* &
                                (r21(i,jyc(n),k)* &
                                (pr(i+1,jyc(n)+1,k)+pr(i+1,jyc(n),k) &
                                -pr(i-1,jyc(n)+1,k)-pr(i-1,jyc(n),k)) &
                                +r23(i,jyc(n),k)* &
                                (pr(i,jyc(n)+1,k+1)+pr(i,jyc(n),k+1) &
                                -pr(i,jyc(n)+1,k-1)-pr(i,jyc(n),k-1))))
                        !
                        end if !free surface <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

                    !
                    end do
                end do

            !-----------------------------------------------------------------------
            !     back and front
            do kk=1,kp

                if (myid==0) then
                    do i=1,jxc(n)
                        do j=1,jyc(n)

                            inv_r33 = 1./r33(i,j,0)

                            pr(i,j,0)=pr(i,j,1) -an*cs5(i,j)*inv_dt*inv_r33 & !/dt/r33(i,j,0)+
                                +coef*inv_r33* &
                                (r31(i,j,0)* &
                                (pr(i+1,j,1)+pr(i+1,j,0)-pr(i-1,j,1)-pr(i-1,j,0)) &
                                +r32(i,j,0)* &
                                (pr(i,j+1,1)+pr(i,j+1,0)-pr(i,j-1,1)-pr(i,j-1,0)))
                        end do
                    end do
                end if

                if (myid==nproc-1) then
                    do i=1,jxc(n)
                        do j=1,jyc(n)

                            inv_r33 = 1./r33(i,j,jzc(n))

                            pr(i,j,jzc(n)+1)=pr(i,j,jzc(n)) +an*cs6(i,j)*inv_dt*inv_r33 & !/dt/r33(i,j,jzc(n))-
                                -coef*inv_r33* &
                                (r31(i,j,jzc(n))* &
                                (pr(i+1,j,jzc(n)+1)+pr(i+1,j,jzc(n)) &
                                -pr(i-1,j,jzc(n)+1)-pr(i-1,j,jzc(n))) &
                                +r32(i,j,jzc(n))* &
                                (pr(i,j+1,jzc(n)+1)+pr(i,j+1,jzc(n)) &
                                -pr(i,j-1,jzc(n)+1)-pr(i,j-1,jzc(n))))
                        end do
                    end do
                end if

            end do
            !
            ! to exchange the necessary points I use a new data type of MPI
            ! avoiding the boundary
            !
            !hicco valuta il seguente commento
            ! questo non va bene per griglia non cartesiana in cui i
            ! bordi sono necessari ---> scambio TUTTO il piano
            ! NO, lo lascio perche' poi si scambiano SOLO gli spigoli
            !
            !     periodicity
            do kk=1,1-kp

                call MPI_TYPE_VECTOR(jyc(n),jxc(n),jxc(n)+2, &
                    MPI_REAL_SD,prplan,ierr)
                call MPI_TYPE_COMMIT(prplan,ierr)


                if (myid==0) then
                    call MPI_SENDRECV(pr(1,1,1),1,prplan,nproc-1,12,pr(1,1,0),1, &
                        prplan,nproc-1,11,MPI_COMM_WORLD,status,ierr)

                else if (myid==nproc-1) then
                    call MPI_SENDRECV(pr(1,1,jzc(n)),1,prplan,0,11,pr(1,1,jzc(n)+1),1, &
                        prplan,0,12,MPI_COMM_WORLD,status,ierr)
                end if

                call MPI_TYPE_FREE(prplan,ierr)

            end do
            !-----------------------------------------------------------------------
            !hicco, vallutare il commento
            !anna versione per condotto non periodico in z e in y
            ! ora devo imporre gli spigoli
            !
            ! direction j is always not periodic
                !
                do kk=1,1-kp   !periodic in k
                    !
                    ! 1) corner line streamwise
                    !
                    !ccc      do i=1,jxc(n)
                    !ccc      pr(i,       0,       0)=pr(i,       0,jzc(n))
                    !ccc      pr(i,       0,jzc(n)+1)=pr(i,       0,     1)
                    !ccc      pr(i,jyc(n)+1,       0)=pr(i,jyc(n)+1,jzc(n))
                    !ccc      pr(i,jyc(n)+1,jzc(n)+1)=pr(i,jyc(n)+1,     1)
                    !ccc      end do
                    !
                    ! 1.1) put values on buffer vector
                    !
                    if (myid==0) then

                        allocate(buffprs1(2*jxc(n)))
                        allocate(buffprr1(2*jxc(n)))
                        do i=1,2*jxc(n)
                            buffprs1(i)=0.
                            buffprr1(i)=0.
                        end do

                        do i=1,jxc(n)
                            buffprs1(i)       =pr(i,jyc(n)+1,1)
                            buffprs1(i+jxc(n))=pr(i,       0,1)
                        end do

                    else if (myid==nproc-1) then

                        allocate(buffprs2(2*jxc(n)))
                        allocate(buffprr2(2*jxc(n)))
                        do i=1,2*jxc(n)
                            buffprs2(i)=0.
                            buffprr2(i)=0.
                        end do

                        do i=1,jxc(n)
                            buffprs2(i)       =pr(i,jyc(n)+1,jzc(n))
                            buffprs2(i+jxc(n))=pr(i,       0,jzc(n))
                        end do

                    end if
                    !
                    !c 1.2) exchange buffer between  PE=0 and PE=nproc-1
                    !
                    if (myid==0) then

                        call MPI_SENDRECV(buffprs1(1),2*jxc(n),MPI_REAL_SD,nproc-1,22,buffprr1(1),2*jxc(n), &
                            MPI_REAL_SD,nproc-1,21,MPI_COMM_WORLD,status,ierr)

                    else if (myid==nproc-1) then

                        call MPI_SENDRECV(buffprs2(1),2*jxc(n),MPI_REAL_SD,0,21,buffprr2(1),2*jxc(n), &
                            MPI_REAL_SD,0,22,MPI_COMM_WORLD,status,ierr)

                    end if
                    !
                    ! 1.3) put values from buffer to variables
                    !
                    if (myid==0) then

                        do i=1,jxc(n)
                            pr(i,jyc(n)+1,0)=buffprr1(i)
                            pr(i,       0,0)=buffprr1(i+jxc(n))
                        end do

                        deallocate(buffprs1,buffprr1)

                    else if (myid==nproc-1) then

                        do i=1,jxc(n)
                            pr(i,jyc(n)+1,jzc(n)+1)=buffprr2(i)
                            pr(i,       0,jzc(n)+1)=buffprr2(i+jxc(n))
                        end do

                        deallocate(buffprs2,buffprr2)

                    end if
                    !
                    ! 2) riquadro di cornice verticale (piani k=0,jzc(n)+1)
                    !
                    do ii=1,1-ip   !periodic in x
                        !
                        !ccc      do j=0,jyc(n)+1
                        !ccc      pr(0,       j,       0)=pr(jxc(n),j,jzc(n))
                        !ccc      pr(0,       j,jzc(n)+1)=pr(jxc(n),j,     1)
                        !ccc      pr(jxc(n)+1,j,       0)=pr(     1,j,jzc(n))
                        !ccc      pr(jxc(n)+1,j,jzc(n)+1)=pr(     1,j,     1)
                        !ccc      end do
                        !
                        ! 2.1) put the values in a buffer vector
                        !
                        if (myid==0) then

                            allocate(buffprs1(2*(jyc(n)+2)))
                            allocate(buffprr1(2*(jyc(n)+2)))
                            do j=1,2*(jyc(n)+2)
                                buffprs1(j)=0.
                                buffprr1(j)=0.
                            end do

                            do j=0,jyc(n)+1
                                buffprs1(j+1)         =pr(jxc(n),j,1)
                                buffprs1(j+1+jyc(n)+2)=pr(     1,j,1)
                            end do

                        else if (myid==nproc-1) then

                            allocate(buffprs2(2*(jyc(n)+2)))
                            allocate(buffprr2(2*(jyc(n)+2)))
                            do j=1,2*(jyc(n)+2)
                                buffprs2(j)=0.
                                buffprr2(j)=0.
                            end do

                            do j=0,jyc(n)+1
                                buffprs2(j+1)         =pr(jxc(n),j,jzc(n))
                                buffprs2(j+1+jyc(n)+2)=pr(     1,j,jzc(n))
                            end do

                        end if
                        !
                        ! 2.2) exchange buffer between PE=0 and PE=nproc-1
                        !
                        if (myid==0) then

                            call MPI_SENDRECV(buffprs1(1),2*(jyc(n)+2),MPI_REAL_SD,nproc-1,32, &
                                buffprr1(1),2*(jyc(n)+2),MPI_REAL_SD,nproc-1,31,MPI_COMM_WORLD,status,ierr)

                        else if (myid==nproc-1) then

                            call MPI_SENDRECV(buffprs2(1),2*(jyc(n)+2),MPI_REAL_SD,0,31, &
                                buffprr2(1),2*(jyc(n)+2),MPI_REAL_SD,0,32,MPI_COMM_WORLD,status,ierr)

                        end if
                        !
                        ! 2.3) put values from buffer to variables
                        !
                        if (myid==0) then

                            do j=0,jyc(n)+1
                                pr(0       ,j,0)=buffprr1(j+1)
                                pr(jxc(n)+1,j,0)=buffprr1(j+1+jyc(n)+2)
                            end do

                            deallocate(buffprs1,buffprr1)

                        else if (myid==nproc-1) then

                            do j=0,jyc(n)+1
                                pr(0       ,j,jzc(n)+1)=buffprr2(j+1)
                                pr(jxc(n)+1,j,jzc(n)+1)=buffprr2(j+1+jyc(n)+2)
                            end do

                            deallocate(buffprs2,buffprr2)

                        end if
                    !
                    end do  !loop on ii
                    !
                    do ii=1,ip
                        !
                        !ccc      do j=0,jyc(n)+1
                        !ccc      pr(0,       j,       0)=pr(0       ,j,jzc(n))
                        !ccc      pr(0,       j,jzc(n)+1)=pr(0       ,j,     1)
                        !ccc      pr(jxc(n)+1,j,       0)=pr(jxc(n)+1,j,jzc(n))
                        !ccc      pr(jxc(n)+1,j,jzc(n)+1)=pr(jxc(n)+1,j,     1)
                        !ccc      end do
                        !
                        ! 2.1) put data on a vector buffer
                        !
                        if (myid==0) then

                            allocate(buffprs1(2*(jyc(n)+2)))
                            allocate(buffprr1(2*(jyc(n)+2)))
                            do j=1,2*(jyc(n)+2)
                                buffprs1(j)=0.
                                buffprr1(j)=0.
                            end do

                            do j=0,jyc(n)+1
                                buffprs1(j+1)         =pr(jxc(n)+1,j,1)
                                buffprs1(j+1+jyc(n)+2)=pr(       0,j,1)
                            end do

                        else if (myid==nproc-1) then

                            allocate(buffprs2(2*(jyc(n)+2)))
                            allocate(buffprr2(2*(jyc(n)+2)))
                            do j=1,2*(jyc(n)+2)
                                buffprs2(j)=0.
                                buffprr2(j)=0.
                            end do

                            do j=0,jyc(n)+1
                                buffprs2(j+1)         =pr(jxc(n)+1,j,jzc(n))
                                buffprs2(j+1+jyc(n)+2)=pr(       0,j,jzc(n))
                            end do

                        end if
                        !
                        ! 2.2) exchange buffer between PE=0 and PE=nproc-1
                        !
                        if (myid==0) then

                            call MPI_SENDRECV(buffprs1(1),2*(jyc(n)+2),MPI_REAL_SD,nproc-1,32, &
                                buffprr1(1),2*(jyc(n)+2),MPI_REAL_SD,nproc-1,31,MPI_COMM_WORLD,status,ierr)

                        else if (myid==nproc-1) then

                            call MPI_SENDRECV(buffprs2(1),2*(jyc(n)+2),MPI_REAL_SD,0,31, &
                                buffprr2(1),2*(jyc(n)+2),MPI_REAL_SD,0,32,MPI_COMM_WORLD,status,ierr)

                        end if
                        !
                        ! 2.3) put values from buffer to variables
                        !
                        if (myid==0) then

                            do j=0,jyc(n)+1
                                pr(jxc(n)+1,j,0)=buffprr1(j+1)
                                pr(       0,j,0)=buffprr1(j+1+jyc(n)+2)
                            end do

                            deallocate(buffprs1,buffprr1)

                        else if (myid==nproc-1) then

                            do j=0,jyc(n)+1
                                pr(jxc(n)+1,j,jzc(n)+1)=buffprr2(j+1)
                                pr(       0,j,jzc(n)+1)=buffprr2(j+1+jyc(n)+2)
                            end do

                            deallocate(buffprs2,buffprr2)

                        end if
                    !
                    end do   !loop on ii
                    !
                    ! 3) horizontal square (plane k=0,jzc(n)+1)
                    !
                    do ii=1,1-ip
                        do k=kstamg(n),kendmg(n)
                            pr(0,       jyc(n)+1,k)=pr(jxc(n),jyc(n)+1,k)
                            pr(0,              0,k)=pr(jxc(n),       0,k)
                            pr(jxc(n)+1,jyc(n)+1,k)=pr(     1,jyc(n)+1,k)
                            pr(jxc(n)+1,       0,k)=pr(     1,       0,k)
                        end do
                    end do  !end loop ii
                    !
                    do ii=1,ip !not periodic in x
                        do k=kstamg(n),kendmg(n)
                            pr(0,       jyc(n)+1,k)=pr(0       ,jyc(n),k)
                            pr(0,              0,k)=pr(0       ,     1,k)
                            pr(jxc(n)+1,jyc(n)+1,k)=pr(jxc(n)+1,jyc(n),k)
                            pr(jxc(n)+1,       0,k)=pr(jxc(n)+1,     1,k)
                        end do
                    end do  !end loop ii

                end do  !end loop kk
                !
                !
                do kk=1,kp !not periodic in k
                    !
                    ! define corner for planes x=1 and x=jxc
                    !
                    ! 1) corner line streamwise
                    !
                    !h      do i=1,jxc(n)
                    !h         pr(i,       0,       0)=pr(i,     1,       0)
                    !h         pr(i,       0,jzc(n)+1)=pr(i,     1,jzc(n)+1)
                    !h         pr(i,jyc(n)+1,       0)=pr(i,jyc(n),       0)
                    !h         pr(i,jyc(n)+1,jzc(n)+1)=pr(i,jyc(n),jzc(n)+1)
                    !h      end do
                    if (myid==0) then
                        do i=1,jxc(n)
                            pr(i,       0,       0)=pr(i,     1,       0)
                            pr(i,jyc(n)+1,       0)=pr(i,jyc(n),       0)
                        end do
                    else if (myid==nproc-1) then
                        do i=1,jxc(n)
                            pr(i,       0,jzc(n)+1)=pr(i,     1,jzc(n)+1)
                            pr(i,jyc(n)+1,jzc(n)+1)=pr(i,jyc(n),jzc(n)+1)
                        end do
                    end if
                    !
                    ! 2) vertical square (planes k=0,jzc(n)+1)
                    !
                    ! periodic in x
                    !
                    !h      do ii=1,1-ip
                    !h      do j=0,jyc(n)+1
                    !h         pr(0,       j,       0)=pr(jxc(n),j,       0)
                    !h         pr(0,       j,jzc(n)+1)=pr(jxc(n),j,jzc(n)+1)
                    !h         pr(jxc(n)+1,j,       0)=pr(     1,j,       0)
                    !h         pr(jxc(n)+1,j,jzc(n)+1)=pr(     1,j,jzc(n)+1)
                    !h      end do
                    !h      end do

                    do ii=1,1-ip
                        if (myid==0) then
                            do j=0,jyc(n)+1
                                pr(0,       j,       0)=pr(jxc(n),j,       0)
                                pr(jxc(n)+1,j,       0)=pr(     1,j,       0)
                            end do
                        else if (myid==nproc-1) then
                            do j=0,jyc(n)+1
                                pr(0,       j,jzc(n)+1)=pr(jxc(n),j,jzc(n)+1)
                                pr(jxc(n)+1,j,jzc(n)+1)=pr(     1,j,jzc(n)+1)
                            end do
                        end if
                    end do
                    !
                    ! not periodic in x
                    !
                    !h      do ii=1,ip
                    !h      do j=0,jyc(n)+1
                    !h         pr(0,       j,       0)=pr(1     ,j,       0)
                    !h         pr(0,       j,jzc(n)+1)=pr(1     ,j,jzc(n)+1)
                    !h         pr(jxc(n)+1,j,       0)=pr(jxc(n),j,       0)
                    !h         pr(jxc(n)+1,j,jzc(n)+1)=pr(jxc(n),j,jzc(n)+1)
                    !h      end do
                    !h      end do

                    do ii=1,ip
                        if (myid==0) then
                            do j=0,jyc(n)+1
                                pr(0,       j,       0)=pr(1     ,j,       0)
                                pr(jxc(n)+1,j,       0)=pr(jxc(n),j,       0)
                            end do
                        else if (myid==nproc-1) then
                            do j=0,jyc(n)+1
                                pr(0,       j,jzc(n)+1)=pr(1     ,j,jzc(n)+1)
                                pr(jxc(n)+1,j,jzc(n)+1)=pr(jxc(n),j,jzc(n)+1)
                            end do
                        end if
                    end do
                    !
                    ! 3) horizontal square (planes k=0,jzc(n)+1)
                    !
                    ! periodic in x
                    !
                    do ii=1,1-ip
                        do k=kstamg(n),kendmg(n)
                            pr(0,       jyc(n)+1,k)=pr(jxc(n),jyc(n)+1,k)
                            pr(0,              0,k)=pr(jxc(n),       0,k)
                            pr(jxc(n)+1,jyc(n)+1,k)=pr(     1,jyc(n)+1,k)
                            pr(jxc(n)+1,       0,k)=pr(     1,       0,k)
                        end do
                    end do
                    !
                    ! not periodic in x
                    !
                    do ii=1,ip
                        do k=kstamg(n),kendmg(n)
                            pr(0,       jyc(n)+1,k)=pr(1     ,jyc(n)+1,k)
                            pr(0,              0,k)=pr(1     ,       0,k)
                            pr(jxc(n)+1,jyc(n)+1,k)=pr(jxc(n),jyc(n)+1,k)
                            pr(jxc(n)+1,       0,k)=pr(jxc(n),       0,k)
                        end do
                    end do
                !
                end do  !end loop kk

            !
            ! exchange k+1 and k-1 at the border
            !anna also for non periodic in x
            do ii=1,ip
                !
                ! 1) generation of buffer vector


                !
                allocate(buff1s(4*jyc(n)))
                allocate(buff2s(4*jyc(n)))
                allocate(buff1r(4*jyc(n)))
                allocate(buff2r(4*jyc(n)))
                do j=1,4*jyc(n)
                    buff1s(j)=0.
                    buff2s(j)=0.
                    buff1r(j)=0.
                    buff2r(j)=0.
                end do

                if (leftpem /= MPI_PROC_NULL) then
                    do j=1,jyc(n) !these are for k+1
                        buff1s(j)=pr(0,j,kstamg(n))
                        buff1s(j+jyc(n))=pr(1,j,kstamg(n))
                        buff1s(j+2*jyc(n))=pr(jxc(n),j,kstamg(n))
                        buff1s(j+3*jyc(n))=pr(jxc(n)+1,j,kstamg(n))
                    end do
                end if

                if (rightpem /= MPI_PROC_NULL) then
                    do j=1,jyc(n) !these are for k-1
                        buff2s(j)=pr(0,j,kendmg(n))
                        buff2s(j+jyc(n))=pr(1,j,kendmg(n))
                        buff2s(j+2*jyc(n))=pr(jxc(n),j,kendmg(n))
                        buff2s(j+3*jyc(n))=pr(jxc(n)+1,j,kendmg(n))
                    end do
                end if
                !
                ! 2) exchange the vector
                !
                if (leftpem /= MPI_PROC_NULL) then
                    call MPI_SEND(buff1s(1),4*jyc(n),MPI_REAL_SD,leftpem,tagls,MPI_COMM_WORLD,ierr)
                end if
                if (rightpem /= MPI_PROC_NULL) then
                    call MPI_RECV(buff1r(1),4*jyc(n),MPI_REAL_SD,rightpem,tagrr,MPI_COMM_WORLD,status,ierr)
                end if
                if (rightpem /= MPI_PROC_NULL) then
                    call MPI_SEND(buff2s(1),4*jyc(n),MPI_REAL_SD,rightpem,tagrs,MPI_COMM_WORLD,ierr)
                end if
                if (leftpem /= MPI_PROC_NULL) then
                    call MPI_RECV(buff2r(1),4*jyc(n),MPI_REAL_SD,leftpem,taglr,MPI_COMM_WORLD,status,ierr)
                end if

                !
                ! 3) reconstruct the planes k-1 and k+1
                !
                if (rightpem /= MPI_PROC_NULL) then
                    do j=1,jyc(n) !these are for k+1
                        pr(0       ,j,kendmg(n)+1)=buff1r(j)
                        pr(1       ,j,kendmg(n)+1)=buff1r(j+jyc(n))
                        pr(jxc(n)  ,j,kendmg(n)+1)=buff1r(j+2*jyc(n))
                        pr(jxc(n)+1,j,kendmg(n)+1)=buff1r(j+3*jyc(n))
                    end do
                end if

                if (leftpem /= MPI_PROC_NULL) then
                    do j=1,jyc(n) !these are for k-1
                        pr(0       ,j,kstamg(n)-1)=buff2r(j)
                        pr(1       ,j,kstamg(n)-1)=buff2r(j+jyc(n))
                        pr(jxc(n)  ,j,kstamg(n)-1)=buff2r(j+2*jyc(n))
                        pr(jxc(n)+1,j,kstamg(n)-1)=buff2r(j+3*jyc(n))
                    end do
                end if

                deallocate(buff1s,buff2s)
                deallocate(buff1r,buff2r)
            !
            end do
            !
            ! direction j is always not periodic
                !
                ! 1) generate the buffer vector
                !
                allocate(buff1s(4*jxc(n)))
                allocate(buff2s(4*jxc(n)))
                allocate(buff1r(4*jxc(n)))
                allocate(buff2r(4*jxc(n)))
                do i=1,4*jxc(n)
                    buff1s(i)=0.
                    buff2s(i)=0.
                    buff1r(i)=0.
                    buff2r(i)=0.
                end do

                if (leftpem /= MPI_PROC_NULL) then
                    do i=1,jxc(n) !these are for k+1
                        buff1s(i)=pr(i,0,kstamg(n))
                        buff1s(i+jxc(n))=pr(i,1,kstamg(n))
                        buff1s(i+2*jxc(n))=pr(i,jyc(n),kstamg(n))
                        buff1s(i+3*jxc(n))=pr(i,jyc(n)+1,kstamg(n))
                    end do
                end if

                if (rightpem /= MPI_PROC_NULL) then
                    do i=1,jxc(n) !these are for k-1
                        buff2s(i)=pr(i,0,kendmg(n))
                        buff2s(i+jxc(n))=pr(i,1,kendmg(n))
                        buff2s(i+2*jxc(n))=pr(i,jyc(n),kendmg(n))
                        buff2s(i+3*jxc(n))=pr(i,jyc(n)+1,kendmg(n))
                    end do
                end if

                !
                ! 2) exchange the vectors
                !
                if (leftpem /= MPI_PROC_NULL) then
                    call MPI_SEND(buff1s(1),4*jxc(n),MPI_REAL_SD,leftpem,tagls,MPI_COMM_WORLD,ierr)
                end if
                if (rightpem /= MPI_PROC_NULL) then
                    call MPI_RECV(buff1r(1),4*jxc(n),MPI_REAL_SD,rightpem,tagrr,MPI_COMM_WORLD,status,ierr)
                end if
                if (rightpem /= MPI_PROC_NULL) then
                    call MPI_SEND(buff2s(1),4*jxc(n),MPI_REAL_SD,rightpem,tagrs,MPI_COMM_WORLD,ierr)
                end if
                if (leftpem /= MPI_PROC_NULL) then
                    call MPI_RECV(buff2r(1),4*jxc(n),MPI_REAL_SD,leftpem,taglr,MPI_COMM_WORLD,status,ierr)
                end if

                !
                ! 3) reconstruct the plane for k-1 and k+1
                !
                if (rightpem /= MPI_PROC_NULL) then
                    do i=1,jxc(n) !these are for k+1
                        pr(i,       0,kendmg(n)+1)=buff1r(i)
                        pr(i,       1,kendmg(n)+1)=buff1r(i+jxc(n))
                        pr(i,  jyc(n),kendmg(n)+1)=buff1r(i+2*jxc(n))
                        pr(i,jyc(n)+1,kendmg(n)+1)=buff1r(i+3*jxc(n))
                    end do
                end if

                if (leftpem /= MPI_PROC_NULL) then
                    do i=1,jxc(n) !these are for k-1
                        pr(i,       0,kstamg(n)-1)=buff2r(i)
                        pr(i,       1,kstamg(n)-1)=buff2r(i+jxc(n))
                        pr(i,  jyc(n),kstamg(n)-1)=buff2r(i+2*jxc(n))
                        pr(i,jyc(n)+1,kstamg(n)-1)=buff2r(i+3*jxc(n))
                    end do
                end if

                deallocate(buff1s,buff2s)
                deallocate(buff1r,buff2r)
        !
        end do ! loop kkk
        !
        return
    end subroutine mul_boun_sndrcv

    subroutine solut_sndrcv_slor(n,i1,j1, &
        kss,jxc,jyc,jzc,pr,rh, &
        cs1,cs2,cs3,cs4,cs5,cs6, &
        r11,r12,r13,r21,r22,r23,r31,r32,r33, &
        i_dx,i_sn,i_av,i_in, &
        kstamg,kendmg,aa,bb,cc)
        !***********************************************************************
        ! line SOR
        ! smoothing on every level with SOR, in eta direction implicit solution

        implicit none

        !-----------------------------------------------------------------------
        !     array declaration
        integer kstamg(4),kendmg(4)
        integer i,j,k,ipot,i1,j1,n,kk
        integer i_dx(i1,j1,kstamg(n):kendmg(n)) !k1)
        integer i_sn(i1,j1,kstamg(n):kendmg(n)) !k1)
        integer i_av(i1,j1,kstamg(n):kendmg(n)) !k1)
        integer i_in(i1,j1,kstamg(n):kendmg(n)) !k1)

        integer kss(4)
        integer jxc(0:4),jyc(0:4),jzc(0:4)
        !
        integer ierr,status(MPI_STATUS_SIZE)
        integer prplan
        integer iii,kkk
        !
        real pot,ppot1,ppot2

        real r11(0:i1,  j1,  kstamg(n):kendmg(n))
        real r12(0:i1,  j1,  kstamg(n):kendmg(n))
        real r13(0:i1,  j1,  kstamg(n):kendmg(n))
        real r21(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r22(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r23(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r31(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r32(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r33(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real pr(0:i1+1,0:j1+1,kstamg(n)-1:kendmg(n)+1)
        real rh(i1,j1,kstamg(n):kendmg(n))

        real cs1(n2,n3),cs2(n2,n3)
        real cs3(n1,n3),cs4(n1,n3)
        real cs5(n1,n2),cs6(n1,n2)

        real an

        real aa(jxc(n),0:jyc(n)+1,kstamg(n):kendmg(n)) !jzc(n))
        real bb(jxc(n),0:jyc(n)+1,kstamg(n):kendmg(n)) !jzc(n))
        real cc(jxc(n),0:jyc(n)+1,kstamg(n):kendmg(n)) !jzc(n))

        real aa0(0:jyc(n)+1)
        real bb0(0:jyc(n)+1)
        real cc0(0:jyc(n)+1)
        real ff0(0:jyc(n)+1)

        integer iterat

        !freesurface = .false.
        !freesurface = 0

        !
        !     define a new data type for MPI to exchange pressure points
        call MPI_TYPE_VECTOR(jyc(n),jxc(n),jxc(n)+2,MPI_REAL_SD,prplan,ierr)
        call MPI_TYPE_COMMIT(prplan,ierr)
        !-----------------------------------------------------------------------


        if (n==1) then
            an=1.
        else
            an=0.
        end if
        !
        ipot=2**(n-1)
        pot=float(ipot)
        ppot1=1/pot
        ppot2=1/pot/pot
        !
        !
        do kk=1,kss(n)
            !
            !     boundary condition

            !
            ! also for line sor I need to compute pressure at the boundary to
            ! construct the gradient for the upgrade of velocity
            !     boundary condition
            call mul_boun_sndrcv(n,i1,j1, &
                jxc,jyc,jzc, &
                r11,r12,r13,r21,r22,r23,r31,r32,r33,pr, &
                kstamg,kendmg,iterat)
            !
            ! smoothing with line SOR zebra with four coulors
            !
            !c      do kcs=1,2
            !c      n1k=mod(kcs,4)
            !
            !c      do ics=1,2
            !c      n1i=mod(ics,4)
            !
            ! start parallel, the number of plane is multiple of n of processors
            !
            ! exchange the boundary values k=0 and k=jzc(n)
            do kkk=1,1-kp

                !c      if (kcs==1) then

                if (myid==nproc-1) then
                    call MPI_SEND(pr(1,1,jzc(n)),1,prplan,0,11,MPI_COMM_WORLD,ierr)
                else if (myid==0) then
                    call MPI_RECV(pr(1,1,0),1,prplan,nproc-1,11,MPI_COMM_WORLD,status,ierr)
                end if

                !c      else if (kcs==2) then

                if (myid==0) then
                    call MPI_SEND(pr(1,1,1),1,prplan,nproc-1,12,MPI_COMM_WORLD,ierr)
                else if (myid==nproc-1) then
                    call MPI_RECV(pr(1,1,jzc(n)+1),1,prplan,0,12,MPI_COMM_WORLD,status,ierr)
                end if

            !c      end if

            end do
            !
            do k=kstamg(n),kendmg(n)
                !cc      do k=(n1k-1)+kstamg(n),kendmg(n),2
                !
                !
                do iii=1,1-ip
                    do j=1,jyc(n)
                        !
                        pr(0,j,k)=pr(jxc(n),j,k)
                        pr(jxc(n)+1,j,k)=pr(1,j,k)
                    !
                    end do
                end do
                !
                !c      do i=n1i,jxc(n),2
                do i=1,jxc(n)
                    !
                    do j=1,jyc(n)
                        !
                        ff0(j)= &
                            -r11(i,j,k) &
                            *pr(i+1,j,k)*i_dx(i,j,k)-(1.-i_dx(i,j,k))*an*cs2(j,k)/dt &
                            -r11(i-1,j,k) &
                            *pr(i-1,j,k)*i_sn(i,j,k)+(1.-i_sn(i,j,k))*an*cs1(j,k)/dt &
                            -.25*r12(i,j,k)*i_dx(i,j,k)   &
                            *(pr(i+1,j+1,k)+pr(i,j+1,k)-pr(i+1,j-1,k)-pr(i,j-1,k)) &
                            -.25*r13(i,j,k)*i_dx(i,j,k)   &
                            *(pr(i+1,j,k+1)+pr(i,j,k+1)-pr(i+1,j,k-1)-pr(i,j,k-1)) &
                            +.25*r12(i-1,j,k)*i_sn(i,j,k) &
                            *(pr(i,j+1,k)+pr(i-1,j+1,k)-pr(i,j-1,k)-pr(i-1,j-1,k)) &
                            +.25*r13(i-1,j,k)*i_sn(i,j,k) &
                            *(pr(i,j,k+1)+pr(i-1,j,k+1)-pr(i,j,k-1)-pr(i-1,j,k-1)) &
                            !
                            -r33(i,j,k) &
                            *pr(i,j,k+1)*i_av(i,j,k)-(1.-i_av(i,j,k))*an*cs6(i,j)/dt &
                            -r33(i,j,k-1) &
                            *pr(i,j,k-1)*i_in(i,j,k)+(1.-i_in(i,j,k))*an*cs5(i,j)/dt &
                            -.25*r31(i,j,k)*i_av(i,j,k)   &
                            *(pr(i+1,j,k+1)+pr(i+1,j,k)-pr(i-1,j,k+1)-pr(i-1,j,k)) &
                            -.25*r32(i,j,k)*i_av(i,j,k)   &
                            *(pr(i,j+1,k+1)+pr(i,j+1,k)-pr(i,j-1,k+1)-pr(i,j-1,k)) &
                            +.25*r31(i,j,k-1)*i_in(i,j,k) &
                            *(pr(i+1,j,k)+pr(i+1,j,k-1)-pr(i-1,j,k)-pr(i-1,j,k-1)) &
                            +.25*r32(i,j,k-1)*i_in(i,j,k) &
                            *(pr(i,j+1,k)+pr(i,j+1,k-1)-pr(i,j-1,k)-pr(i,j-1,k-1)) &
                            !
                            -.25*r21(i,j,k)  &
                            *(pr(i+1,j+1,k)+pr(i+1,j,k)-pr(i-1,j+1,k)-pr(i-1,j,k)) &
                            -.25*r23(i,j,k)   &
                            *(pr(i,j+1,k+1)+pr(i,j,k+1)-pr(i,j+1,k-1)-pr(i,j,k-1)) &
                            +.25*r21(i,j-1,k) &
                            *(pr(i+1,j,k)+pr(i+1,j-1,k)-pr(i-1,j,k)-pr(i-1,j-1,k)) &
                            +.25*r23(i,j-1,k) &
                            *(pr(i,j,k+1)+pr(i,j-1,k+1)-pr(i,j,k-1)-pr(i,j-1,k-1))
                        !
                        ff0(j)=ff0(j)*ppot2+rh(i,j,k)
                    end do

                    !     bottom aa=0
                    ff0(0)=(-an*cs3(i,k)/dt & !source term at the side
                        +.25*r21(i,0,k)* &
                        (pr(i+1,1,k)+pr(i+1,0,k)-pr(i-1,1,k)-pr(i-1,0,k)) &
                        +.25*r23(i,0,k)* &
                        (pr(i,1,k+1)+pr(i,0,k+1)-pr(i,1,k-1)-pr(i,0,k-1))       &
                        )*ppot2

                    !     upper cc=0
                    ff0(jyc(n)+1)=(an*cs4(i,k)/dt &
                        -.25*r21(i,jyc(n),k) &
                        *(pr(i+1,jyc(n)+1,k)+pr(i+1,jyc(n),k) &
                        - pr(i-1,jyc(n)+1,k)-pr(i-1,jyc(n),k)) &
                        -.25*r23(i,jyc(n),k) &
                        *(pr(i,jyc(n)+1,k+1)+pr(i,jyc(n),k+1) &
                        - pr(i,jyc(n)+1,k-1)-pr(i,jyc(n),k-1))   &
                        )*ppot2

                    do j=0,jyc(n)+1
                        aa0(j)=aa(i,j,k)
                        bb0(j)=bb(i,j,k)
                        cc0(j)=cc(i,j,k)
                    end do
                    !
                    call tridag(aa0,bb0,cc0,ff0,jyc(n)+2)
                    !
                    !-----------------------------------------------------------------------
                    ! compute new pr with slor
                    !
                    do j=0,jyc(n)+1
                        pr(i,j,k)=pr(i,j,k)+omega*(ff0(j)-pr(i,j,k))
                    end do
                !
                !
                end do   ! done one complete sweep for 1 plane
            end do   ! done one complete sweep for 1 plane
            !
            !ccc      end do   ! done the 2 colors

            !-----------------------------------------------------------------------
            !c      if (kcs==1) then
            !
            if (leftpem /= MPI_PROC_NULL) then
                call MPI_SEND(pr(1,1,kstamg(n)),1, &
                    prplan,leftpem,tagls, &
                    MPI_COMM_WORLD,ierr)
            end if
            if (rightpem /= MPI_PROC_NULL) then
                call MPI_RECV(pr(1,1,kendmg(n)+1),1, &
                    prplan,rightpem,tagrr, &
                    MPI_COMM_WORLD,status,ierr)
            end if

            !c      else if (kcs==2) then
            !
            if (rightpem /= MPI_PROC_NULL) then
                call MPI_SEND(pr(1,1,kendmg(n)),1, &
                    prplan,rightpem,tagrs, &
                    MPI_COMM_WORLD,ierr)
            end if
            if (leftpem /= MPI_PROC_NULL) then
                call MPI_RECV(pr(1,1,kstamg(n)-1),1, &
                    prplan,leftpem,taglr, &
                    MPI_COMM_WORLD,status,ierr)
            end if

        !
        !c      end if
        !
        ! compute again values k=1 and k=jzc(n)
        !
        !ccc      end do   ! done the 2 colors
        !
        end do   ! end of a pseudo time iteration
        !
        call MPI_TYPE_FREE(prplan,ierr)
        !
        !
        if (leftpem /= MPI_PROC_NULL) then
            call MPI_SEND(pr(0,0,kstamg(n)),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,leftpem,tagls,MPI_COMM_WORLD,ierr)
        end if
        if (rightpem /= MPI_PROC_NULL) then
            call MPI_RECV(pr(0,0,kendmg(n)+1),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,rightpem,tagrr,MPI_COMM_WORLD,status,ierr)
        end if
        if (rightpem /= MPI_PROC_NULL) then
            call MPI_SEND(pr(0,0,kendmg(n)),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,rightpem,tagrs,MPI_COMM_WORLD,ierr)
        end if
        if (leftpem /= MPI_PROC_NULL) then
            call MPI_RECV(pr(0,0,kstamg(n)-1),(jxc(n)+2)*(jyc(n)+2), &
                MPI_REAL_SD,leftpem,taglr,MPI_COMM_WORLD,status,ierr)
        end if


        !-----------------------------------------------------------------------
        return
    end

    subroutine mul_met(nlevel,jxc,jyc,jzc)
        !***********************************************************************
        ! coefficent computation for multigrid
        ! settings for 4 level
        !
        use myarrays_metri3
        use myarrays_velo3
        !
        implicit none

        !-----------------------------------------------------------------------
        ! arrays declaration
        integer i,j,k,ic,jc,kc,i1,i2,j1,j2,k1,k2,n
        integer nlevel
        real pot,t11,t22,t33
        real xcsi,ycsi,zcsi
        real xeta,yeta,zeta
        real xzet,yzet,zzet
        real xsop,xsot,ysop,ysot,zsop,zsot
        real xav,xdt,yav,ydt,zav,zdt
        real xsn,xdx,ysn,ydx,zsn,zdx
        real x0,x1,x2
        real y0,y1,y2
        real z0,z1,z2
        !
        integer jxc(0:4),jyc(0:4),jzc(0:4)
        !      integer inizio

        !integer kpstamg(0:4),kpendmg(0:4),ncolprocmg(0:4)
        !integer kfacepstamg(0:4)
        !-----------------------------------------------------------------------
        ! allocation

        !     sett kparasta and kparaend for each multigrid level
        !     k parallel start multigrid -> kpstamg
        !     k parallel end multigrid   -> kpstamg
        do n=1,nlevel
            ncolprocmg(n) = jzc(n)/nproc
            kpstamg(n) = myid*ncolprocmg(n)+1
            kpendmg(n) = (myid+1)*ncolprocmg(n)
            !        only myid=0 has kfacepstamg = 0
            kfacepstamg(n) = kpstamg(n)-1
        !    if (myid==0)kfacepstamg(n) = kpstamg(n) -1
        end do

        !-----------------------------------------------------------------------
        if (nlevel >=1) then
            allocate(in_dx1(n1  ,n2  ,kpstamg(1):kpendmg(1)))
            allocate(in_sn1(n1  ,n2  ,kpstamg(1):kpendmg(1)))
            allocate(in_sp1(n1  ,n2  ,kpstamg(1):kpendmg(1)))
            allocate(in_st1(n1  ,n2  ,kpstamg(1):kpendmg(1)))
            allocate(in_av1(n1  ,n2  ,kpstamg(1):kpendmg(1)))
            allocate(in_in1(n1  ,n2  ,kpstamg(1):kpendmg(1)))

            in_dx1 = 0
            in_sn1 = 0
            in_sp1 = 0
            in_st1 = 0
            in_av1 = 0
            in_in1 = 0

            allocate(aa1(n1  ,0:n2+1  ,kpstamg(1):kpendmg(1)))
            allocate(bb1(n1  ,0:n2+1  ,kpstamg(1):kpendmg(1)))
            allocate(cc1(n1  ,0:n2+1  ,kpstamg(1):kpendmg(1)))

            aa1 = 0.
            bb1 = 0.
            cc1 = 0.

            allocate(den_1(n1  ,  n2  ,    kpstamg(1):kpendmg(1)))
            den_1 = 0.

        end if
        !-----------------------------------------------------------------------
        if (nlevel >=2) then
            allocate(in_dx2(n1/2,n2/2,kpstamg(2):kpendmg(2)))
            allocate(in_sn2(n1/2,n2/2,kpstamg(2):kpendmg(2)))
            allocate(in_sp2(n1/2,n2/2,kpstamg(2):kpendmg(2)))
            allocate(in_st2(n1/2,n2/2,kpstamg(2):kpendmg(2)))
            allocate(in_av2(n1/2,n2/2,kpstamg(2):kpendmg(2)))
            allocate(in_in2(n1/2,n2/2,kpstamg(2):kpendmg(2)))

            allocate(g11_2(0:n1/2,  n2/2,    kpstamg(2):kpendmg(2)))
            allocate(g12_2(0:n1/2,  n2/2,    kpstamg(2):kpendmg(2)))
            allocate(g13_2(0:n1/2,  n2/2,    kpstamg(2):kpendmg(2)))
            allocate(g21_2(  n1/2,0:n2/2,    kpstamg(2):kpendmg(2)))
            allocate(g22_2(  n1/2,0:n2/2,    kpstamg(2):kpendmg(2)))
            allocate(g23_2(  n1/2,0:n2/2,    kpstamg(2):kpendmg(2)))
            allocate(g31_2(  n1/2,  n2/2,kfacepstamg(2):kpendmg(2)))
            allocate(g32_2(  n1/2,  n2/2,kfacepstamg(2):kpendmg(2)))
            allocate(g33_2(  n1/2,  n2/2,kfacepstamg(2):kpendmg(2)))

            in_dx2 = 0
            in_sn2 = 0
            in_sp2 = 0
            in_st2 = 0
            in_av2 = 0
            in_in2 = 0

            g11_2 = 0.
            g12_2 = 0.
            g13_2 = 0.
            g21_2 = 0.
            g22_2 = 0.
            g23_2 = 0.
            g31_2 = 0.
            g32_2 = 0.
            g33_2 = 0.

            allocate(aa2(n1/2,0:n2/2+1,kpstamg(2):kpendmg(2)))
            allocate(bb2(n1/2,0:n2/2+1,kpstamg(2):kpendmg(2)))
            allocate(cc2(n1/2,0:n2/2+1,kpstamg(2):kpendmg(2)))

            aa2 = 0.
            bb2 = 0.
            cc2 = 0.

            allocate(den_2(n1/2,  n2/2,    kpstamg(2):kpendmg(2)))
            den_2 = 0.

        end if
        !-----------------------------------------------------------------------
        if (nlevel >=3) then
            allocate(in_dx3(n1/4,n2/4,kpstamg(3):kpendmg(3)))
            allocate(in_sn3(n1/4,n2/4,kpstamg(3):kpendmg(3)))
            allocate(in_sp3(n1/4,n2/4,kpstamg(3):kpendmg(3)))
            allocate(in_st3(n1/4,n2/4,kpstamg(3):kpendmg(3)))
            allocate(in_av3(n1/4,n2/4,kpstamg(3):kpendmg(3)))
            allocate(in_in3(n1/4,n2/4,kpstamg(3):kpendmg(3)))

            allocate(g11_3(0:n1/4,  n2/4,    kpstamg(3):kpendmg(3)))
            allocate(g12_3(0:n1/4,  n2/4,    kpstamg(3):kpendmg(3)))
            allocate(g13_3(0:n1/4,  n2/4,    kpstamg(3):kpendmg(3)))
            allocate(g21_3(  n1/4,0:n2/4,    kpstamg(3):kpendmg(3)))
            allocate(g22_3(  n1/4,0:n2/4,    kpstamg(3):kpendmg(3)))
            allocate(g23_3(  n1/4,0:n2/4,    kpstamg(3):kpendmg(3)))
            allocate(g31_3(  n1/4,  n2/4,kfacepstamg(3):kpendmg(3)))
            allocate(g32_3(  n1/4,  n2/4,kfacepstamg(3):kpendmg(3)))
            allocate(g33_3(  n1/4,  n2/4,kfacepstamg(3):kpendmg(3)))

            in_dx3 = 0
            in_sn3 = 0
            in_sp3 = 0
            in_st3 = 0
            in_av3 = 0
            in_in3 = 0

            g11_3 = 0.
            g12_3 = 0.
            g13_3 = 0.
            g21_3 = 0.
            g22_3 = 0.
            g23_3 = 0.
            g31_3 = 0.
            g32_3 = 0.
            g33_3 = 0.

            allocate(aa3(n1/4,0:n2/4+1,kpstamg(3):kpendmg(3)))
            allocate(bb3(n1/4,0:n2/4+1,kpstamg(3):kpendmg(3)))
            allocate(cc3(n1/4,0:n2/4+1,kpstamg(3):kpendmg(3)))

            aa3 = 0.
            bb3 = 0.
            cc3 = 0.

            allocate(den_3(n1/4,  n2/4,    kpstamg(3):kpendmg(3)))
            den_3 = 0.

        end if
        !-----------------------------------------------------------------------
        if (nlevel >=4) then
            allocate(in_dx4(n1/8,n2/8,kpstamg(4):kpendmg(4)))
            allocate(in_sn4(n1/8,n2/8,kpstamg(4):kpendmg(4)))
            allocate(in_sp4(n1/8,n2/8,kpstamg(4):kpendmg(4)))
            allocate(in_st4(n1/8,n2/8,kpstamg(4):kpendmg(4)))
            allocate(in_av4(n1/8,n2/8,kpstamg(4):kpendmg(4)))
            allocate(in_in4(n1/8,n2/8,kpstamg(4):kpendmg(4)))

            allocate(g11_4(0:n1/8,  n2/8,    kpstamg(4):kpendmg(4)))
            allocate(g12_4(0:n1/8,  n2/8,    kpstamg(4):kpendmg(4)))
            allocate(g13_4(0:n1/8,  n2/8,    kpstamg(4):kpendmg(4)))
            allocate(g21_4(  n1/8,0:n2/8,    kpstamg(4):kpendmg(4)))
            allocate(g22_4(  n1/8,0:n2/8,    kpstamg(4):kpendmg(4)))
            allocate(g23_4(  n1/8,0:n2/8,    kpstamg(4):kpendmg(4)))
            allocate(g31_4(  n1/8,  n2/8,kfacepstamg(4):kpendmg(4)))
            allocate(g32_4(  n1/8,  n2/8,kfacepstamg(4):kpendmg(4)))
            allocate(g33_4(  n1/8,  n2/8,kfacepstamg(4):kpendmg(4)))

            in_dx4 = 0
            in_sn4 = 0
            in_sp4 = 0
            in_st4 = 0
            in_av4 = 0
            in_in4 = 0

            g11_4 = 0.
            g12_4 = 0.
            g13_4 = 0.
            g21_4 = 0.
            g22_4 = 0.
            g23_4 = 0.
            g31_4 = 0.
            g32_4 = 0.
            g33_4 = 0.

            allocate(aa4(n1/8,0:n2/8+1,kpstamg(4):kpendmg(4)))
            allocate(bb4(n1/8,0:n2/8+1,kpstamg(4):kpendmg(4)))
            allocate(cc4(n1/8,0:n2/8+1,kpstamg(4):kpendmg(4)))

            aa4 = 0.
            bb4 = 0.
            cc4 = 0.

            allocate(den_4(n1/8,  n2/8,    kpstamg(4):kpendmg(4)))
            den_4 = 0.

        end if
        !-----------------------------------------------------------------------
        !
        ! work for other level on g11,g12,g13
        !
        do n=2,nlevel

            !
            do i=0,jxc(n)
                do j=1,jyc(n)
                    do k=kpstamg(n),kpendmg(n) !1,jzc(n) !
                        !
                        ! plane at csi constant
                        !
                        j2=2* j   *2**(n-2)
                        j1=2*(j-1)*2**(n-2)
                        !
                        k2=2* k   *2**(n-2)
                        k1=2*(k-1)*2**(n-2)
                        !
                        ic=2* i   *2**(n-2)
                        !
                        if (i==0.and.ip==1) then
                            !
                            i1=2*(i+1)*2**(n-2)
                            i2=2*(i+2)*2**(n-2)
                            !
                            x2=.25*(x(i2,j2,k2)+x(i2,j2,k1) &
                                +x(i2,j1,k2)+x(i2,j1,k1))
                            x1=.25*(x(i1,j2,k2)+x(i1,j2,k1) &
                                +x(i1,j1,k2)+x(i1,j1,k1))
                            x0=.25*(x(0 ,j2,k2)+x(0 ,j2,k1) &
                                +x(0 ,j1,k2)+x(0 ,j1,k1))
                            !
                            y2=.25*(y(i2,j2,k2)+y(i2,j2,k1) &
                                +y(i2,j1,k2)+y(i2,j1,k1))
                            y1=.25*(y(i1,j2,k2)+y(i1,j2,k1) &
                                +y(i1,j1,k2)+y(i1,j1,k1))
                            y0=.25*(y(0 ,j2,k2)+y(0 ,j2,k1) &
                                +y(0 ,j1,k2)+y(0 ,j1,k1))

                            z2=.25*(z(i2,j2,k2)+z(i2,j2,k1) &
                                +z(i2,j1,k2)+z(i2,j1,k1))
                            z1=.25*(z(i1,j2,k2)+z(i1,j2,k1) &
                                +z(i1,j1,k2)+z(i1,j1,k1))
                            z0=.25*(z(0 ,j2,k2)+z(0 ,j2,k1) &
                                +z(0 ,j1,k2)+z(0 ,j1,k1))
                            !
                            xcsi=.5 * ( -3.*x0 + 4.*x1 - x2 )
                            ycsi=.5 * ( -3.*y0 + 4.*y1 - y2 )
                            zcsi=.5 * ( -3.*z0 + 4.*z1 - z2 )
                        !
                        else if (i==jxc(n).and.ip==1) then
                            !
                            i1=2*(i-1)*2**(n-2)
                            i2=2*(i-2)*2**(n-2)
                            !
                            x2=.25*(x(i2,j2,k2)+x(i2,j2,k1) &
                                +x(i2,j1,k2)+x(i2,j1,k1))
                            x1=.25*(x(i1,j2,k2)+x(i1,j2,k1) &
                                +x(i1,j1,k2)+x(i1,j1,k1))
                            x0=.25*(x(n1,j2,k2)+x(n1,j2,k1) &
                                +x(n1,j1,k2)+x(n1,j1,k1))
                            !
                            y2=.25*(y(i2,j2,k2)+y(i2,j2,k1) &
                                +y(i2,j1,k2)+y(i2,j1,k1))
                            y1=.25*(y(i1,j2,k2)+y(i1,j2,k1) &
                                +y(i1,j1,k2)+y(i1,j1,k1))
                            y0=.25*(y(n1,j2,k2)+y(n1,j2,k1) &
                                +y(n1,j1,k2)+y(n1,j1,k1))
                            !
                            z2=.25*(z(i2,j2,k2)+z(i2,j2,k1) &
                                +z(i2,j1,k2)+z(i2,j1,k1))
                            z1=.25*(z(i1,j2,k2)+z(i1,j2,k1) &
                                +z(i1,j1,k2)+z(i1,j1,k1))
                            z0=.25*(z(n1,j2,k2)+z(n1,j2,k1) &
                                +z(n1,j1,k2)+z(n1,j1,k1))
                            !
                            xcsi=.5 * ( 3.*x0 - 4.*x1 + x2 )
                            ycsi=.5 * ( 3.*y0 - 4.*y1 + y2 )
                            zcsi=.5 * ( 3.*z0 - 4.*z1 + z2 )
                        !
                        else
                            !
                            i2=2*(i+1)*2**(n-2)
                            i1=2*(i-1)*2**(n-2)
                            !
                            xdx=.25*(x(i2,j2,k2)+x(i2,j2,k1) &
                                +x(i2,j1,k2)+x(i2,j1,k1))
                            xsn=.25*(x(i1,j2,k2)+x(i1,j2,k1) &
                                +x(i1,j1,k2)+x(i1,j1,k1))
                            !
                            ydx=.25*(y(i2,j2,k2)+y(i2,j2,k1) &
                                +y(i2,j1,k2)+y(i2,j1,k1))
                            ysn=.25*(y(i1,j2,k2)+y(i1,j2,k1) &
                                +y(i1,j1,k2)+y(i1,j1,k1))
                            !
                            zdx=.25*(z(i2,j2,k2)+z(i2,j2,k1) &
                                +z(i2,j1,k2)+z(i2,j1,k1))
                            zsn=.25*(z(i1,j2,k2)+z(i1,j2,k1) &
                                +z(i1,j1,k2)+z(i1,j1,k1))
                            !
                            xcsi=.5*(xdx-xsn)
                            ycsi=.5*(ydx-ysn)
                            zcsi=.5*(zdx-zsn)
                        !
                        end if
                        !
                        xeta=.5*(x(ic,j2,k2) + x(ic,j2,k1))- &
                            .5*(x(ic,j1,k2) + x(ic,j1,k1))
                        !
                        yeta=.5*(y(ic,j2,k2) + y(ic,j2,k1))- &
                            .5*(y(ic,j1,k2) + y(ic,j1,k1))
                        !
                        zeta=.5*(z(ic,j2,k2) + z(ic,j2,k1))- &
                            .5*(z(ic,j1,k2) + z(ic,j1,k1))
                        !
                        xzet=.5*(x(ic,j2,k2) + x(ic,j1,k2))- &
                            .5*(x(ic,j2,k1) + x(ic,j1,k1))
                        !
                        yzet=.5*(y(ic,j2,k2) + y(ic,j1,k2))- &
                            .5*(y(ic,j2,k1) + y(ic,j1,k1))
                        !
                        zzet=.5*(z(ic,j2,k2) + z(ic,j1,k2))- &
                            .5*(z(ic,j2,k1) + z(ic,j1,k1))
                        !
                        ! compute controvariant metric tensor terms on other grid (g11,g12,g13)
                        !
                        call gprima(xcsi,ycsi,zcsi,xeta,yeta,zeta,xzet,yzet,zzet, &
                            t11,t22,t33)
                        !
                        if (n==2) then
                            !
                            pot=2.
                            g11_2(i,j,k)=t11/pot
                            g12_2(i,j,k)=t22/pot
                            g13_2(i,j,k)=t33/pot
                        !
                        else if (n==3) then
                            !
                            pot=4.
                            g11_3(i,j,k)=t11/pot
                            g12_3(i,j,k)=t22/pot
                            g13_3(i,j,k)=t33/pot
                        !
                        else if (n==4) then
                            !
                            pot=8.
                            g11_4(i,j,k)=t11/pot
                            g12_4(i,j,k)=t22/pot
                            g13_4(i,j,k)=t33/pot
                        !
                        end if
                                    !
                    end do
                end do
            end do
                    !
        end do            !
        !-----------------------------------------------------------------------
        !
        ! work for other level on g21,g22,g23

        !
        do n=2,nlevel
            !
            ! planes at eta constant
            !
            do i=1,jxc(n)
                do j=0,jyc(n)
                    do k=kpstamg(n),kpendmg(n) !1,jzc(n)
                        !
                        i2=2* i   *2**(n-2)
                        i1=2*(i-1)*2**(n-2)
                        !
                        k2=2* k   *2**(n-2)
                        k1=2*(k-1)*2**(n-2)
                        !
                        jc=2* j   *2**(n-2)
                        !
                        if      (j==0)  then
                            !
                            j1=2*(j+1)*2**(n-2)
                            j2=2*(j+2)*2**(n-2)
                            !
                            x2=.25*(x(i2,j2,k2)+x(i2,j2,k1) &
                                +x(i1,j2,k1)+x(i1,j2,k2))
                            x1=.25*(x(i2,j1,k2)+x(i2,j1,k1) &
                                +x(i1,j1,k1)+x(i1,j1,k2))
                            x0=.25*(x(i2,j ,k2)+x(i2,j ,k1) &
                                +x(i1,j ,k1)+x(i1,j ,k2))
                            !
                            y2=.25*(y(i2,j2,k2)+y(i2,j2,k1) &
                                +y(i1,j2,k1)+y(i1,j2,k2))
                            y1=.25*(y(i2,j1,k2)+y(i2,j1,k1) &
                                +y(i1,j1,k1)+y(i1,j1,k2))
                            y0=.25*(y(i2,j ,k2)+y(i2,j ,k1) &
                                +y(i1,j ,k1)+y(i1,j ,k2))
                            !
                            z2=.25*(z(i2,j2,k2)+z(i2,j2,k1) &
                                +z(i1,j2,k1)+z(i1,j2,k2))
                            z1=.25*(z(i2,j1,k2)+z(i2,j1,k1) &
                                +z(i1,j1,k1)+z(i1,j1,k2))
                            z0=.25*(z(i2,j ,k2)+z(i2,j ,k1) &
                                +z(i1,j ,k1)+z(i1,j ,k2))
                            !
                            xeta=.5 * ( -3.*x0 + 4.*x1 - x2 )
                            yeta=.5 * ( -3.*y0 + 4.*y1 - y2 )
                            zeta=.5 * ( -3.*z0 + 4.*z1 - z2 )
                        !
                        else if (j==jyc(n)) then
                            !
                            j1=2*(j-1)*2**(n-2)
                            j2=2*(j-2)*2**(n-2)
                            !
                            x2=.25*(x(i2,j2,k2)+x(i2,j2,k1) &
                                +x(i1,j2,k1)+x(i1,j2,k2))
                            x1=.25*(x(i2,j1,k2)+x(i2,j1,k1) &
                                +x(i1,j1,k1)+x(i1,j1,k2))
                            x0=.25*(x(i2,n2,k2)+x(i2,n2,k1) &
                                +x(i1,n2,k1)+x(i1,n2,k2))
                            !
                            y2=.25*(y(i2,j2,k2)+y(i2,j2,k1) &
                                +y(i1,j2,k1)+y(i1,j2,k2))
                            y1=.25*(y(i2,j1,k2)+y(i2,j1,k1) &
                                +y(i1,j1,k1)+y(i1,j1,k2))
                            y0=.25*(y(i2,n2,k2)+y(i2,n2,k1) &
                                +y(i1,n2,k1)+y(i1,n2,k2))
                            !
                            z2=.25*(z(i2,j2,k2)+z(i2,j2,k1) &
                                +z(i1,j2,k1)+z(i1,j2,k2))
                            z1=.25*(z(i2,j1,k2)+z(i2,j1,k1) &
                                +z(i1,j1,k1)+z(i1,j1,k2))
                            z0=.25*(z(i2,n2,k2)+z(i2,n2,k1) &
                                +z(i1,n2,k1)+z(i1,n2,k2))
                            !
                            xeta=.5 * ( 3.*x0 - 4.*x1 + x2 )
                            yeta=.5 * ( 3.*y0 - 4.*y1 + y2 )
                            zeta=.5 * ( 3.*z0 - 4.*z1 + z2 )
                        !
                        else
                            !
                            j2=2*(j+1)*2**(n-2)
                            j1=2*(j-1)*2**(n-2)
                            !
                            xsop=.25*(x(i2,j2,k2)+x(i2,j2,k1) &
                                +x(i1,j2,k1)+x(i1,j2,k2))
                            xsot=.25*(x(i2,j1,k2)+x(i2,j1,k1) &
                                +x(i1,j1,k1)+x(i1,j1,k2))
                            !
                            ysop=.25*(y(i2,j2,k2)+y(i2,j2,k1) &
                                +y(i1,j2,k1)+y(i1,j2,k2))
                            ysot=.25*(y(i2,j1,k2)+y(i2,j1,k1) &
                                +y(i1,j1,k1)+y(i1,j1,k2))
                            !
                            zsop=.25*(z(i2,j2,k2)+z(i2,j2,k1) &
                                +z(i1,j2,k1)+z(i1,j2,k2))
                            zsot=.25*(z(i2,j1,k2)+z(i2,j1,k1) &
                                +z(i1,j1,k1)+z(i1,j1,k2))
                            !
                            xeta=.5*(xsop-xsot)
                            yeta=.5*(ysop-ysot)
                            zeta=.5*(zsop-zsot)
                        !
                        end if
                        !
                        yzet=.5*(y(i2,jc,k2) + y(i1,jc,k2))- &
                            .5*(y(i2,jc,k1) + y(i1,jc,k1))
                        !
                        zcsi=.5*(z(i2,jc,k2) + z(i2,jc,k1))- &
                            .5*(z(i1,jc,k2) + z(i1,jc,k1))
                        !
                        ycsi=.5*(y(i2,jc,k2) + y(i2,jc,k1))- &
                            .5*(y(i1,jc,k2) + y(i1,jc,k1))
                        !
                        zzet=.5*(z(i2,jc,k2) + z(i1,jc,k2))- &
                            .5*(z(i2,jc,k1) + z(i1,jc,k1))
                        !
                        xcsi=.5*(x(i2,jc,k2) + x(i2,jc,k1))- &
                            .5*(x(i1,jc,k2) + x(i1,jc,k1))
                        !
                        xzet=.5*(x(i2,jc,k2) + x(i1,jc,k2))- &
                            .5*(x(i2,jc,k1) + x(i1,jc,k1))
                        !
                        call gseconda(xcsi,ycsi,zcsi,xeta,yeta,zeta,xzet,yzet,zzet,t11,t22,t33)
                        if (n==2) then
                            !
                            pot=2.
                            g21_2(i,j,k)=t11/pot
                            g22_2(i,j,k)=t22/pot
                            g23_2(i,j,k)=t33/pot
                        !
                        else if (n==3) then
                            !
                            pot=4.
                            g21_3(i,j,k)=t11/pot
                            g22_3(i,j,k)=t22/pot
                            g23_3(i,j,k)=t33/pot
                        !
                        else if (n==4) then
                            !
                            pot=8.
                            g21_4(i,j,k)=t11/pot
                            g22_4(i,j,k)=t22/pot
                            g23_4(i,j,k)=t33/pot
                        !
                        end if
                                            !
                    end do
                end do
            end do
        end do
        !
        !
        !-----------------------------------------------------------------------
        !
        ! work for other level on g31,g32,g33
        !
        do n=2,nlevel
            !
            ! planes at zeta constant
            !

            do i=1,jxc(n)
                do j=1,jyc(n)
                    do k=kfacepstamg(n),kpendmg(n) !for myid=0 start from 0 !inizio,jzc(n)
                        !
                        i2=2* i   *2**(n-2)
                        i1=2*(i-1)*2**(n-2)
                        !
                        j2=2* j   *2**(n-2)
                        j1=2*(j-1)*2**(n-2)
                        !
                        kc=2* k   *2**(n-2)

                        !
                        if (k==0.and.kp==1) then
                            !
                            k1=2*(k+1)*2**(n-2)
                            k2=2*(k+2)*2**(n-2)
                            !
                            x2=.25*(x(i2,j2,k2)+x(i2,j1,k2) &
                                +x(i1,j1,k2)+x(i1,j2,k2))
                            x1=.25*(x(i2,j2,k1)+x(i2,j1,k1) &
                                +x(i1,j1,k1)+x(i1,j2,k1))
                            x0=.25*(x(i2,j2,k )+x(i2,j1,k ) &
                                +x(i1,j1,k )+x(i1,j2,k ))
                            !
                            y2=.25*(y(i2,j2,k2)+y(i2,j1,k2) &
                                +y(i1,j1,k2)+y(i1,j2,k2))
                            y1=.25*(y(i2,j2,k1)+y(i2,j1,k1) &
                                +y(i1,j1,k1)+y(i1,j2,k1))
                            y0=.25*(y(i2,j2,k )+y(i2,j1,k ) &
                                +y(i1,j1,k )+y(i1,j2,k ))
                            !
                            z2=.25*(z(i2,j2,k2)+z(i2,j1,k2) &
                                +z(i1,j1,k2)+z(i1,j2,k2))
                            z1=.25*(z(i2,j2,k1)+z(i2,j1,k1) &
                                +z(i1,j1,k1)+z(i1,j2,k1))
                            z0=.25*(z(i2,j2,k )+z(i2,j1,k ) &
                                +z(i1,j1,k )+z(i1,j2,k ))
                            !
                            xzet=.5 * ( -3.*x0 + 4.*x1 - x2 )
                            yzet=.5 * ( -3.*y0 + 4.*y1 - y2 )
                            zzet=.5 * ( -3.*z0 + 4.*z1 - z2 )
                        !
                        else if (k==jzc(n).and.kp==1 &
                            .and.myid==(nproc-1)) then
                            !
                            k1=2*(k-1)*2**(n-2)
                            k2=2*(k-2)*2**(n-2)
                            !
                            x2=.25*(x(i2,j2,k2)+x(i2,j1,k2) &
                                +x(i1,j1,k2)+x(i1,j2,k2))
                            x1=.25*(x(i2,j2,k1)+x(i2,j1,k1) &
                                +x(i1,j1,k1)+x(i1,j2,k1))
                            x0=.25*(x(i2,j2,n3)+x(i2,j1,n3) &
                                +x(i1,j1,n3)+x(i1,j2,n3))
                            !
                            y2=.25*(y(i2,j2,k2)+y(i2,j1,k2) &
                                +y(i1,j1,k2)+y(i1,j2,k2))
                            y1=.25*(y(i2,j2,k1)+y(i2,j1,k1) &
                                +y(i1,j1,k1)+y(i1,j2,k1))
                            y0=.25*(y(i2,j2,n3)+y(i2,j1,n3) &
                                +y(i1,j1,n3)+y(i1,j2,n3))
                            !
                            z2=.25*(z(i2,j2,k2)+z(i2,j1,k2) &
                                +z(i1,j1,k2)+z(i1,j2,k2))
                            z1=.25*(z(i2,j2,k1)+z(i2,j1,k1) &
                                +z(i1,j1,k1)+z(i1,j2,k1))
                            z0=.25*(z(i2,j2,n3)+z(i2,j1,n3) &
                                +z(i1,j1,n3)+z(i1,j2,n3))
                            !
                            xzet=.5 * ( 3.*x0 - 4.*x1 + x2 )
                            yzet=.5 * ( 3.*y0 - 4.*y1 + y2 )
                            zzet=.5 * ( 3.*z0 - 4.*z1 + z2 )
                        !
                        else
                            !
                            !
                            k2=2*(k+1)*2**(n-2)
                            k1=2*(k-1)*2**(n-2)
                            !

                            xav=.25*(x(i2,j2,k2)+x(i2,j1,k2) &
                                +x(i1,j1,k2)+x(i1,j2,k2))
                            xdt=.25*(x(i2,j2,k1)+x(i2,j1,k1) &
                                +x(i1,j1,k1)+x(i1,j2,k1))
                            !
                            yav=.25*(y(i2,j2,k2)+y(i2,j1,k2) &
                                +y(i1,j1,k2)+y(i1,j2,k2))
                            ydt=.25*(y(i2,j2,k1)+y(i2,j1,k1) &
                                +y(i1,j1,k1)+y(i1,j2,k1))
                            !
                            zav=.25*(z(i2,j2,k2)+z(i2,j1,k2) &
                                +z(i1,j1,k2)+z(i1,j2,k2))
                            zdt=.25*(z(i2,j2,k1)+z(i2,j1,k1) &
                                +z(i1,j1,k1)+z(i1,j2,k1))
                            !
                            xzet=.5*(xav-xdt)
                            yzet=.5*(yav-ydt)
                            zzet=.5*(zav-zdt)
                        !
                        end if
                        !
                        ycsi=.5*(y(i2,j2,kc) + y(i2,j1,kc))- &
                            .5*(y(i1,j2,kc) + y(i1,j1,kc))
                        !
                        zeta=.5*(z(i2,j2,kc) + z(i1,j2,kc))- &
                            .5*(z(i2,j1,kc) + z(i1,j1,kc))
                        !
                        yeta=.5*(y(i2,j2,kc) + y(i1,j2,kc))- &
                            .5*(y(i2,j1,kc) + y(i1,j1,kc))
                        !
                        zcsi=.5*(z(i2,j2,kc) + z(i2,j1,kc))- &
                            .5*(z(i1,j2,kc) + z(i1,j1,kc))
                        !
                        xcsi=.5*(x(i2,j2,kc) + x(i2,j1,kc))- &
                            .5*(x(i1,j2,kc) + x(i1,j1,kc))
                        !
                        xeta=.5*(x(i2,j2,kc) + x(i1,j2,kc))- &
                            .5*(x(i2,j1,kc) + x(i1,j1,kc))
                        !
                        call gterza(xcsi,ycsi,zcsi,xeta,yeta,zeta,xzet,yzet,zzet,t11,t22,t33)
                        !
                        if (n==2) then
                            !
                            pot=2.
                            g31_2(i,j,k)=t11/pot
                            g32_2(i,j,k)=t22/pot
                            g33_2(i,j,k)=t33/pot
                        !
                        else if (n==3) then
                            !
                            pot=4.
                            g31_3(i,j,k)=t11/pot
                            g32_3(i,j,k)=t22/pot
                            g33_3(i,j,k)=t33/pot
                        !
                        else if (n==4) then
                            !
                            pot=8.
                            g31_4(i,j,k)=t11/pot
                            g32_4(i,j,k)=t22/pot
                            g33_4(i,j,k)=t33/pot
                        !
                        end if
                                                    !
                    end do
                end do
            end do
        end do
                !-----------------------------------------------------------------------

        do n=1,nlevel

            if (n==1) then
                do k=kpstamg(n),kpendmg(n)
                    do j=1,jyc(n)
                        do i=1,jxc(n)

                            den_1(i,j,k)=1./(g11(i,j,k)+g11(i-1,j,k) &
                                +g22(i,j,k)+g22(i,j-1,k) &
                                +g33(i,j,k)+g33(i,j,k-1))

                        end do
                    end do
                end do
            end if

            if (n==2) then
                do k=kpstamg(n),kpendmg(n)
                    do j=1,jyc(n)
                        do i=1,jxc(n)

                            den_2(i,j,k)=1./(g11_2(i,j,k)+g11_2(i-1,j,k) &
                                +g22_2(i,j,k)+g22_2(i,j-1,k) &
                                +g33_2(i,j,k)+g33_2(i,j,k-1))

                        end do
                    end do
                end do
            end if

            if (n==3) then
                do k=kpstamg(n),kpendmg(n)
                    do j=1,jyc(n)
                        do i=1,jxc(n)

                            den_3(i,j,k)=1./(g11_3(i,j,k)+g11_3(i-1,j,k) &
                                +g22_3(i,j,k)+g22_3(i,j-1,k) &
                                +g33_3(i,j,k)+g33_3(i,j,k-1))

                        end do
                    end do
                end do
            end if

            if (n==4) then
                do k=kpstamg(n),kpendmg(n)
                    do j=1,jyc(n)
                        do i=1,jxc(n)

                            den_4(i,j,k)=1./(g11_4(i,j,k)+g11_4(i-1,j,k) &
                                +g22_4(i,j,k)+g22_4(i,j-1,k) &
                                +g33_4(i,j,k)+g33_4(i,j,k-1))

                        end do
                    end do
                end do
            end if

        end do
        !-----------------------------------------------------------------------
        return

    end subroutine mul_met

    subroutine mul_ini(n1,n2,n12,n13,n14,n22,n23,n24,rhs1,rhs2,rhs3,rhs4,pr2,pr3,pr4,kstamg,kendmg)
        !***********************************************************************
        ! matrix initialization for multigrid
        !
        implicit none
        !-----------------------------------------------------------------------
        ! array declaration
        integer,intent(in) :: n1,n2,n12,n13,n14,n22,n23,n24
        integer kstamg(4),kendmg(4)
        integer i,j,k
        real rhs1(n1 ,n2 ,kstamg(1):kendmg(1)) !n3)
        real rhs2(n12,n22,kstamg(2):kendmg(2)) !n32)
        real rhs3(n13,n23,kstamg(3):kendmg(3)) !n33)
        real rhs4(n14,n24,kstamg(4):kendmg(4)) !n34)
        !
        real pr2(0:n12+1,0:n22+1,kstamg(2)-1:kendmg(2)+1) !0:n32+1)
        real pr3(0:n13+1,0:n23+1,kstamg(3)-1:kendmg(3)+1) !0:n33+1)
        real pr4(0:n14+1,0:n24+1,kstamg(4)-1:kendmg(4)+1) !0:n34+1)

        !-----------------------------------------------------------------------
        ! matrix initialization
        !
        do k=kstamg(1),kendmg(1) !1,n3
            do j=1,n2
                do i=1,n1
                    !
                    rhs1(i,j,k)=0.
                !
                end do
            end do
        end do
        !
        do k=kstamg(2),kendmg(2) !1,n32
            do j=1,n22
                do i=1,n12
                    !
                    rhs2(i,j,k)=0.
                !
                end do
            end do
        end do
        !
        do k=kstamg(2)-1,kendmg(2)+1  !0,n32+1
            do j=0,n22+1
                do i=0,n12+1
                    !
                    pr2(i,j,k)=0.
                !
                end do
            end do
        end do
        !
        do k=kstamg(3),kendmg(3) !1,n33
            do j=1,n23
                do i=1,n13
                    !
                    rhs3(i,j,k)=0.
                !
                end do
            end do
        end do
        !
        do k=kstamg(3)-1,kendmg(3)+1  !0,n33+1
            do j=0,n23+1
                do i=0,n13+1
                    !
                    pr3(i,j,k)=0.
                !
                end do
            end do
        end do
        !
        do k=kstamg(4),kendmg(4) !1,n34
            do j=1,n24
                do i=1,n14
                    !
                    rhs4(i,j,k)=0.
                !
                end do
            end do
        end do
        !
        do k=kstamg(4)-1,kendmg(4)+1  !0,n34+1
            do j=0,n24+1
                do i=0,n14+1
                    !
                    pr4(i,j,k)=0.
                !
                end do
            end do
        end do
        !
        return

    end subroutine mul_ini

    subroutine wall(nlevel,jxc,jyc,jzc)
        !***********************************************************************
        ! set index for computation of pressure index, this is done at the sides
        ! and an all the grid
        !
        use myarrays_metri3
        !

        implicit none
        !
        !-----------------------------------------------------------------------
        !     variables declaration
        integer ix,iy,iz,n
        integer ierr
        integer nlevel
        integer jxc(0:4),jyc(0:4),jzc(0:4)

        integer n11,n21,n31
        integer n12,n22,n32
        integer n13,n23,n33
        integer n14,n24,n34
        !
        integer kpstamg(0:4),kpendmg(0:4),ncolprocmg(0:4)
        integer kfacepstamg(0:4)
        !-----------------------------------------------------------------------

        do n=1,nlevel
            ncolprocmg(n) = jzc(n)/nproc
            kpstamg(n) = myid*ncolprocmg(n)+1
            kpendmg(n) = (myid+1)*ncolprocmg(n)
            kfacepstamg(n) = kpstamg(n) -1
        !    if (myid==0)kfacepstamg(n) = kpstamg(n) -1
        end do

        call MPI_BARRIER(MPI_COMM_WORLD,ierr)

        n11=n1
        n21=n2
        n31=ncolperproc

        n12=n1/2
        n22=n2/2
        n32=ncolperproc/2

        n13=n1/4
        n23=n2/4
        n33=ncolperproc/4

        n14=n1/8
        n24=n2/8
        n34=ncolperproc/8

        ! for all the grids
        !
        do n=1,nlevel
            !
            ix=jxc(n)
            iy=jyc(n)
            iz=jzc(n)
            !
            if (n==1) then
                !
                call sett(myid,nproc,n,kpstamg(n),kpendmg(n),kfacepstamg(n), &
                    ix,iy,iz,n11,n21,n31,   &
                    in_dx1,in_sn1,in_sp1, &
                    in_st1,in_av1,in_in1, &
                    g11,g22,g33,aa1,bb1,cc1)
            !
            else if (n==2) then
                !
                call sett(myid,nproc,n,kpstamg(n),kpendmg(n),kfacepstamg(n), &
                    ix,iy,iz,n12,n22,n32, &
                    in_dx2,in_sn2,in_sp2, &
                    in_st2,in_av2,in_in2, &
                    g11_2,g22_2,g33_2,aa2,bb2,cc2)
            !
            else if (n==3) then
                !
                call sett(myid,nproc,n,kpstamg(n),kpendmg(n),kfacepstamg(n), &
                    ix,iy,iz,n13,n23,n33, &
                    in_dx3,in_sn3,in_sp3, &
                    in_st3,in_av3,in_in3, &
                    g11_3,g22_3,g33_3,aa3,bb3,cc3)
            !
            else if (n==4) then
                !
                call sett(myid,nproc,n,kpstamg(n),kpendmg(n),kfacepstamg(n), &
                    ix,iy,iz,n14,n24,n34, &
                    in_dx4,in_sn4,in_sp4, &
                    in_st4,in_av4,in_in4, &
                    g11_4,g22_4,g33_4,aa4,bb4,cc4)
            !
            end if
        !
        end do
        !
        return
    end subroutine wall

    subroutine potenziale_ibm(tipo)

        !***********************************************************************
        ! pressure correction inside Immersed Boundary is setted equal to that
        ! outside
        !-----------------------------------------------------------------------
        use myarrays_velo3
        !

        implicit none

        !-----------------------------------------------------------------------
        !     array declaration
        integer i,j,k
        integer ierr,status(MPI_STATUS_SIZE)
        integer conto_ib

        integer tipo(0:n1+1,0:n2+1,kparasta-deepl:kparaend+deepr)

        real fi_old
        !-----------------------------------------------------------------------
        !     solid cell  fi(solida)=fi(ib)

        do k=kparasta,kparaend
            do j=1,n2
                do i=1,n1

                    if (tipo(i,j,k)==0) then
                        fi_old = fi(i,j,k)
                        fi(i,j,k)=0.
                        conto_ib=0

                        if (tipo(i+1,j  ,k  )==1) then
                            fi(i  ,j  ,k  )=fi(i,j,k)+fi(i+1,j  ,k  )
                            conto_ib=conto_ib+1
                        end if

                        if (tipo(i-1,j  ,k  )==1) then
                            fi(i  ,j  ,k  )=fi(i,j,k)+fi(i-1,j  ,k  )
                            conto_ib=conto_ib+1
                        end if

                        if (tipo(i  ,j+1,k  )==1) then
                            fi(i  ,j  ,k  )=fi(i,j,k)+fi(i  ,j+1,k  )
                            conto_ib=conto_ib+1
                        end if

                        if (tipo(i  ,j-1,k  )==1) then
                            fi(i  ,j  ,k  )=fi(i,j,k)+fi(i  ,j-1,k  )
                            conto_ib=conto_ib+1
                        end if

                        if (tipo(i  ,j  ,k+1)==1) then
                            fi(i  ,j  ,k  )=fi(i,j,k)+fi(i  ,j  ,k+1)
                            conto_ib=conto_ib+1
                        end if

                        if (tipo(i  ,j  ,k-1)==1) then
                            fi(i  ,j  ,k  )=fi(i,j,k)+fi(i  ,j  ,k-1)
                            conto_ib=conto_ib+1
                        end if

                        if (conto_ib/=0) then
                            fi(i,j,k)=fi(i,j,k)/conto_ib
                        else
                            fi(i,j,k)=fi_old
                        end if

                    end if

                end do
            end do
        end do

        !     send left
        if (myid/=0) then
            call MPI_SEND(fi(0,0,kparasta),(n1+2)*(n2+2),MPI_REAL_SD,leftpe,tagls,MPI_COMM_WORLD,ierr)
        end if
        if (myid/=nproc-1) then
            call MPI_RECV(fi(0,0,kparaend+1),(n1+2)*(n2+2),MPI_REAL_SD,rightpe,tagrr,MPI_COMM_WORLD,status,ierr)
        end if

        !     send right
        if (myid/=nproc-1) then
            call MPI_SEND(fi(0,0,kparaend),(n1+2)*(n2+2),MPI_REAL_SD,rightpe,tagrs,MPI_COMM_WORLD,ierr)
        end if
        if (myid/=0) then
            call MPI_RECV(fi(0,0,kparasta-1),(n1+2)*(n2+2),MPI_REAL_SD,leftpe,taglr,MPI_COMM_WORLD,status,ierr)
        end if

        return

    end subroutine potenziale_ibm

    subroutine gprima(xcsi,ycsi,zcsi,xeta,yeta,zeta,xzet,yzet,zzet,t11,t22,t33)
        !***********************************************************************
        !
        ! compute the first line elements of controvariant metric tensor on
        ! higher grid level for multigrid
        !
        implicit none
        !
        !-----------------------------------------------------------------------
        !     variables declaration
        real giac,t11,t22,t33
        real xcsi,ycsi,zcsi
        real xeta,yeta,zeta
        real xzet,yzet,zzet
        real csx,csy,csz
        real etx,ety,etz
        real ztx,zty,ztz
        !-----------------------------------------------------------------------
        !
        giac=     xcsi*(yeta*zzet-yzet*zeta)- &
            xeta*(ycsi*zzet-yzet*zcsi)+ &
            xzet*(ycsi*zeta-yeta*zcsi)
        !
        csx = yeta*zzet - yzet*zeta
        csy = xzet*zeta - xeta*zzet
        csz = xeta*yzet - xzet*yeta
        !
        etx = yzet*zcsi - ycsi*zzet
        ety = xcsi*zzet - xzet*zcsi
        etz = xzet*ycsi - xcsi*yzet
        !
        ztx=ycsi*zeta-yeta*zcsi
        zty=xeta*zcsi-xcsi*zeta
        ztz=xcsi*yeta-xeta*ycsi
        !
        t11=(csx**2+csy**2+csz**2)/giac
        !
        t22=(csx*etx+csy*ety+csz*etz)/giac
        !
        t33=(csx*ztx+csy*zty+csz*ztz)/giac
        !
        return
    end subroutine gprima

    subroutine gseconda(xcsi,ycsi,zcsi,xeta,yeta,zeta,xzet,yzet,zzet,t11,t22,t33)
        !
        ! compute the second line elements of controvariant metric tensor on
        ! higher grid level for multigrid
        !
        implicit none
        !
        !-----------------------------------------------------------------------
        !     variables declaration
        real giac,t11,t22,t33
        real xcsi,ycsi,zcsi
        real xeta,yeta,zeta
        real xzet,yzet,zzet
        real csx,csy,csz
        real etx,ety,etz
        real ztx,zty,ztz
        !-----------------------------------------------------------------------
        !
        etx = yzet*zcsi - ycsi*zzet
        ety = xcsi*zzet - xzet*zcsi
        etz = xzet*ycsi - xcsi*yzet
        !
        csx = yeta*zzet - yzet*zeta
        csy = xzet*zeta - xeta*zzet
        csz = xeta*yzet - xzet*yeta
        !
        ztx=ycsi*zeta-yeta*zcsi
        zty=xeta*zcsi-xcsi*zeta
        ztz=xcsi*yeta-xeta*ycsi
        !
        giac=xcsi*(yeta*zzet-yzet*zeta)- &
            xeta*(ycsi*zzet-yzet*zcsi)+ &
            xzet*(ycsi*zeta-yeta*zcsi)
        !
        t11=(etx*csx+ety*csy+etz*csz)/giac
        !
        t22=(etx**2+ety**2+etz**2)/giac
        !
        t33=(etx*ztx+ety*zty+etz*ztz)/giac
        !
        return
    end subroutine gseconda

    subroutine gterza(xcsi,ycsi,zcsi,xeta,yeta,zeta,xzet,yzet,zzet,t11,t22,t33)
        !***********************************************************************
        !
        ! compute the elements for the third line of the controvariant
        ! metric tensor for upper grid for multigrid cycle
        !
        implicit none
        !
        !-----------------------------------------------------------------------
        !     variables declaration
        real giac,t11,t22,t33
        real xcsi,ycsi,zcsi
        real xeta,yeta,zeta
        real xzet,yzet,zzet
        real csx,csy,csz
        real etx,ety,etz
        real ztx,zty,ztz
        !-----------------------------------------------------------------------
        !
        csx = yeta*zzet - yzet*zeta
        csy = xzet*zeta - xeta*zzet
        csz = xeta*yzet - xzet*yeta
        !
        etx = yzet*zcsi - ycsi*zzet
        ety = xcsi*zzet - xzet*zcsi
        etz = xzet*ycsi - xcsi*yzet
        !
        ztx=  ycsi*zeta - yeta*zcsi
        zty=  xeta*zcsi - xcsi*zeta
        ztz=  xcsi*yeta - xeta*ycsi
        !
        giac=     xcsi*(yeta*zzet-yzet*zeta)- &
            xeta*(ycsi*zzet-yzet*zcsi)+ &
            xzet*(ycsi*zeta-yeta*zcsi)
        !
        t11=(ztx*csx+zty*csy+ztz*csz)/giac
        !
        t22=(ztx*etx+zty*ety+ztz*etz)/giac
        !
        t33=(ztx**2+zty**2+ztz**2)/giac
        !
        return
    end subroutine gterza

    subroutine restrict_sndrcv(n,i1,j1,i2,j2,jxc,jyc,rh,rh1,kstamg,kendmg)
        !***********************************************************************
        ! compute residual on lower level grid
        ! restriction operation with average value
        !
        implicit none
        !
        !-----------------------------------------------------------------------
        !     array declaration
        integer ierr
        integer kstamg(4),kendmg(4)
        !
        integer i,j,k,id,jd,kd,n,i1,j1,i2,j2
        integer jxc(0:4),jyc(0:4)
        real  rh(i1,j1,kstamg(n):kendmg(n)) !k1)
        real rh1(i2,j2,kstamg(n+1):kendmg(n+1)) !k2)

        real inv_8


        !-----------------------------------------------------------------------
        inv_8 = 1./8.

        do k=kstamg(n+1),kendmg(n+1)
            do j=1,jyc(n+1)
                do i=1,jxc(n+1)
                    !
                    id=2*i
                    jd=2*j
                    kd=2*k
                    !
                    rh1(i,j,k)=rh(id  ,jd  ,kd  ) &
                        +rh(id-1,jd  ,kd  ) &
                        +rh(id  ,jd-1,kd  ) &
                        +rh(id-1,jd-1,kd  ) &
                        +rh(id  ,jd  ,kd-1) &
                        +rh(id-1,jd  ,kd-1) &
                        +rh(id  ,jd-1,kd-1) &
                        +rh(id-1,jd-1,kd-1)
                    !
                    rh1(i,j,k)=-rh1(i,j,k)*inv_8
                !
                end do
            end do
        end do
        !
        return

    end subroutine restrict_sndrcv

    subroutine resid_sndrcv(n,i1,j1,jxc,jyc,pr,rh1,rh,r11,r22,r33,kstamg,kendmg)
        !***********************************************************************
        ! compute residuals on current grid
        !
        implicit none

        !-----------------------------------------------------------------------
        !     array declaration
        integer kstamg(4),kendmg(4)
        integer i,j,k,n,i1,j1,ipot
        integer jxc(0:4),jyc(0:4)
        !
        real res_av,res_ind,res_sot,res_sop,res_sn,res_dx
        real pot,inv_pot,inv_dt,coef
        real r11(0:i1,  j1,  kstamg(n):kendmg(n))
        real r12(0:i1,  j1,  kstamg(n):kendmg(n))
        real r13(0:i1,  j1,  kstamg(n):kendmg(n))
        real r21(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r22(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r23(i1  ,0:j1,  kstamg(n):kendmg(n))
        real r31(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r32(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real r33(i1  ,  j1,kstamg(n)-1:kendmg(n))
        real pr(0:i1+1,0:j1+1,kstamg(n)-1:kendmg(n)+1) !0:k1+1)
        real rh(i1,j1,kstamg(n):kendmg(n))  !k1)
        real rh1(i1,j1,kstamg(n):kendmg(n)) !k1)

        real an

        !
        integer ierr
        !

        !-----------------------------------------------------------------------

        ipot=2**(n-1)
        pot=float(ipot)

        inv_pot = 1./pot
        inv_dt  = 1./dt

        coef = 0.25

        if (n==1) then
            an=1.
        else
            an=0.
        end if
        !-----------------------------------------------------------------------
        !
        do k=kstamg(n),kendmg(n)
            do j=1,jyc(n)
                do i=1,jxc(n)
                    !
                    !      residual right
                    res_dx=( &
                        r11(i,j,k)*(pr(i+1,j,k)-pr(i,j,k))   &
                        +coef* &
                        (r12(i,j,k)* &
                        (pr(i+1,j+1,k)+pr(i,j+1,k)-pr(i+1,j-1,k)-pr(i,j-1,k)) &
                        +r13(i,j,k)* &
                        (pr(i+1,j,k+1)+pr(i,j,k+1)-pr(i+1,j,k-1)-pr(i,j,k-1)) &
                        ))*inv_pot
                    !
                    !      left residual
                    res_sn=( &
                        r11(i-1,j,k)*(pr(i,j,k)-pr(i-1,j,k))     &
                        +coef* &
                        (r12(i-1,j,k)* &
                        (pr(i,j+1,k)+pr(i-1,j+1,k)-pr(i,j-1,k)-pr(i-1,j-1,k)) &
                        +r13(i-1,j,k)* &
                        (pr(i,j,k+1)+pr(i-1,j,k+1)-pr(i,j,k-1)-pr(i-1,j,k-1)) &
                        ))*inv_pot
                    !
                    !      upper residual
                    res_sop=( &
                        r22(i,j,k)*(pr(i,j+1,k)-pr(i,j,k))    &
                        +coef* &
                        (r21(i,j,k)* &
                        (pr(i+1,j+1,k)+pr(i+1,j,k)-pr(i-1,j+1,k)-pr(i-1,j,k)) &
                        +r23(i,j,k)* &
                        (pr(i,j+1,k+1)+pr(i,j,k+1)-pr(i,j+1,k-1)-pr(i,j,k-1)) &
                        ))*inv_pot
                    !
                    !     bottom residual
                    res_sot=( &
                        r22(i,j-1,k)*(pr(i,j,k)-pr(i,j-1,k)) &
                        +coef* &
                        (r21(i,j-1,k)* &
                        (pr(i+1,j,k)+pr(i+1,j-1,k)-pr(i-1,j,k)-pr(i-1,j-1,k)) &
                        +r23(i,j-1,k)* &
                        (pr(i,j,k+1)+pr(i,j-1,k+1)-pr(i,j,k-1)-pr(i,j-1,k-1)) &
                        ))*inv_pot
                    !
                    !     front residual
                    res_av=( &
                        r33(i,j,k)*(pr(i,j,k+1)-pr(i,j,k))   &
                        +coef* &
                        (r31(i,j,k)* &
                        (pr(i+1,j,k+1)+pr(i+1,j,k)-pr(i-1,j,k+1)-pr(i-1,j,k)) &
                        +r32(i,j,k)* &
                        (pr(i,j+1,k+1)+pr(i,j+1,k)-pr(i,j-1,k+1)-pr(i,j-1,k)) &
                        ))*inv_pot
                    !
                    !     back residual
                    res_ind=( &
                        r33(i,j,k-1)*(pr(i,j,k)-pr(i,j,k-1)) &
                        +coef* &
                        (r31(i,j,k-1)* &
                        (pr(i+1,j,k)+pr(i+1,j,k-1)-pr(i-1,j,k)-pr(i-1,j,k-1)) &
                        +r32(i,j,k-1)* &
                        (pr(i,j+1,k)+pr(i,j+1,k-1)-pr(i,j-1,k)-pr(i,j-1,k-1)) &
                        ))*inv_pot
                    !
                    rh1(i,j,k)= &
                        (res_dx  - res_sn  +  &
                        res_sop - res_sot + &
                        res_av  - res_ind )*inv_pot - rh(i,j,k)
                !
                end do
            end do
        end do
        !-----------------------------------------------------------------------

        return

    end subroutine resid_sndrcv

    subroutine sett(myid,nproc,n,ksta,kend,kfsta,ix,iy,iz,nx,ny,nz, &
        i_dx,i_sn,i_sp,i_st,i_av,i_in, &
        r11,r22,r33,aa,bb,cc)
        !***********************************************************************
        !     set index
        !
        implicit none

        !-----------------------------------------------------------------------
        !     variables declaration
        integer ksta,kend,kfsta
        integer i,j,k
        integer ix,iy,iz
        integer nx,ny,nz

        integer i_dx(nx,ny,ksta:kend)
        integer i_sn(nx,ny,ksta:kend)
        integer i_sp(nx,ny,ksta:kend)
        integer i_st(nx,ny,ksta:kend)
        integer i_av(nx,ny,ksta:kend)
        integer i_in(nx,ny,ksta:kend)

        real  aa(nx,0:ny+1,ksta:kend)
        real  bb(nx,0:ny+1,ksta:kend)
        real  cc(nx,0:ny+1,ksta:kend)

        real r11(0:nx,ny,ksta:kend)
        real r22(nx,0:ny,ksta:kend)
        real r33(nx,ny,kfsta:kend)

        integer ipot
        real pot,ppot1,ppot2
        integer n,myid,nproc

        !-----------------------------------------------------------------------
        !
        ! in all the field
        !
        do k=ksta,kend
            do j=1,ny
                do i=1,nx
                    !
                    i_dx(i,j,k) =1
                    i_sn(i,j,k) =1
                    i_sp(i,j,k) =1
                    i_st(i,j,k) =1
                    i_av(i,j,k) =1
                    i_in(i,j,k) =1
                !
                end do
            end do
        end do
        !
        ! index sides sn and dx (1 and 2), general periodicity
        !
        do j=1,ny
            do k=ksta,kend
                !
                i_sn(1 ,j,k) =1-ip
                i_dx(ix,j,k) =1-ip
                    !
            end do
        end do
        !
        ! index sides bottom and upper (3 and 4), no periodicity
        !
        do i=1,nx
            do k=ksta,kend
                !
                i_st(i,1 ,k) =0
                i_sp(i,iy,k) =0
                        !
            end do
        end do
        !
        ! index sides back and front (6 and 5), general periodicity

        !hicco MA SIAMO SICUI CHE SIANO COSI' INDIETRO E AVANTI?????
        !hicco DOVREBBE ESSERE IL CONTRARIO !!!!!!!

        ! indici parete  indietro e avanti: (periodicita generalizzata)
        !
        if (myid==0) then
            do j=1,ny
                do i=1,nx
                    i_in(i,j,ksta) =1-kp
                end do
            end do
        else if (myid==nproc-1) then
            write(*,*)'IZ,NZ',iz,nz,ksta,kend
            do j=1,ny
                do i=1,nx
                    i_av(i,j,kend) =1-kp
                end do
            end do
        end if

        !-----------------------------------------------------------------------
        ! for multigrid in case of line sor in j direction (implict solution)
        ! build fixed coefficent for the tridiagonal matrix
        !
        ipot=2**(n-1)
        pot=float(ipot)
        ppot1=1/pot
        ppot2=1/pot/pot

        do k=ksta,kend !1,nz
            do i=1,nx

                do j=1,ny
                    aa(i,j,k)=ppot2*r22(i,j-1,k)
                    bb(i,j,k)=-ppot2*(r22(i  ,j,k  )+r22(i,j-1,k) &
                        +r11(i  ,j,k  )*i_dx(i,j,k) &
                        +r11(i-1,j,k  )*i_sn(i,j,k) &
                        +r33(i  ,j,k  )*i_av(i,j,k) &
                        +r33(i  ,j,k-1)*i_in(i,j,k))
                    cc(i,j,k)=ppot2*r22(i,j,k)
                end do

                !     side bottom (3) aa=0
                aa(i,0,k)= 0.
                bb(i,0,k)= r22(i,0,k)*ppot2
                cc(i,0,k)=-r22(i,0,k)*ppot2

                !     side upper (4) cc=0
                aa(i,ny+1,k)=-r22(i,ny,k)*ppot2
                bb(i,ny+1,k)= r22(i,ny,k)*ppot2
                cc(i,ny+1,k)= 0.

            end do
        end do

        return

    end subroutine sett

    subroutine prolong(n,i1,j1,i2,j2,jxc,jyc,prf,pr,kstamg,kendmg)
    !***********************************************************************
    ! prolongation operation from coarse grid to fine one with bilinear
    ! interpolation
    !

    implicit none
    !

    !-----------------------------------------------------------------------
    !     array declaration
    integer kstamg(4),kendmg(4)
    integer i,j,k,i1,j1,i2,j2,n,if,jf,kf
    integer jxc(0:4),jyc(0:4)
    real a1,a2,a3,a4,a5,a6,a7,a8
    real inv_64
    real prf(0:i1+1,0:j1+1,kstamg(n  )-1:kendmg(n  )+1) !0:k1+1)
    real  pr(0:i2+1,0:j2+1,kstamg(n+1)-1:kendmg(n+1)+1) !0:k2+1)

    integer kstamg0(4)
    integer ierr,status(MPI_STATUS_SIZE)
    integer plantypef
    !-----------------------------------------------------------------------
    !
    !     prf pressure on fine grid
    !     pr  pressure on coarse grid
    !
    call MPI_TYPE_VECTOR(jyc(n)+1,jxc(n)+1,jxc(n)+2, &
        MPI_REAL_SD,plantypef,ierr)
    call MPI_TYPE_COMMIT(plantypef,ierr)

    if (myid==0) then
        kstamg0(n+1)=0
    else if (myid==nproc-1) then
        kstamg0(n+1)=kstamg(n+1)
    else if ((myid/=0).and.(myid/=nproc-1)) then
        kstamg0(n+1)=kstamg(n+1)
    end if


    inv_64 = 1./64.

    do k=kstamg0(n+1),kendmg(n+1)
        do j=0,jyc(n+1)
            do i=0,jxc(n+1)
                !
                if=2*i
                jf=2*j
                kf=2*k
                !
                a1=27.
                a2=9.
                a3=9.
                a4=9.
                a5=3.
                a6=3.
                a7=3.
                a8=1.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64


                if=2*i+1
                jf=2*j
                kf=2*k
                !
                a1=9.
                a2=27.
                a3=3.
                a4=3.
                a5=9.
                a6=9.
                a7=1.
                a8=3.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64
                !
                !
                if=2*i
                jf=2*j+1
                kf=2*k
                !
                a1=9.
                a2=3.
                a3=27.
                a4=3.
                a5=9.
                a6=1.
                a7=9.
                a8=3.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64
                !
                !
                if=2*i
                jf=2*j
                kf=2*k+1
                !
                a1=9.
                a2=3.
                a3=3.
                a4=27.
                a5=1.
                a6=9.
                a7=9.
                a8=3.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64
                !
                !
                if=2*i+1
                jf=2*j+1
                kf=2*k
                !
                a1=3.
                a2=9.
                a3=9.
                a4=1.
                a5=27.
                a6=3.
                a7=3.
                a8=9.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64
                !
                !
                if=2*i+1
                jf=2*j
                kf=2*k+1
                !
                a1=3.
                a2=9.
                a3=1.
                a4=9.
                a5=3.
                a6=27.
                a7=3.
                a8=9.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64
                !
                !
                if=2*i+1
                jf=2*j+1
                kf=2*k+1
                !
                a1=1.
                a2=3.
                a3=3.
                a4=3.
                a5=9.
                a6=9.
                a7=9.
                a8=27.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64
                !
                !
                if=2*i
                jf=2*j+1
                kf=2*k+1
                !
                a1=3.
                a2=1.
                a3=9.
                a4=9.
                a5=3.
                a6=3.
                a7=27.
                a8=9.
                !
                prf(if,jf,kf)=prf(if,jf,kf)+ &
                    (  a1*pr(i  ,j  ,k  )+ &
                    a2*pr(i+1,j  ,k  )+ &
                    a3*pr(i  ,j+1,k  )+ &
                    a4*pr(i  ,j  ,k+1)+ &
                    a5*pr(i+1,j+1,k  )+ &
                    a6*pr(i+1,j  ,k+1)+ &
                    a7*pr(i  ,j+1,k+1)+ &
                    a8*pr(i+1,j+1,k+1) )*inv_64
            !
            end do
        end do
    end do
    !
    ! before exchange I need to collocate in the proper position
    ! the plane computed by each procs which belong to its right
    !
    if (rightpem /= MPI_PROC_NULL) then
        call MPI_SEND(prf(0,0,kendmg(n)+1),1, &
            plantypef,rightpem,tagrs,MPI_COMM_WORLD,ierr)
    end if
    if (leftpem /= MPI_PROC_NULL) then
        call MPI_RECV(prf(0,0,kstamg(n)),1, &
            plantypef,leftpem,taglr,MPI_COMM_WORLD,status,ierr)
    end if

    if (rightpem /= MPI_PROC_NULL) then
        call MPI_SEND(prf(0,0,kendmg(n)),1, &
            plantypef,rightpem,tagrs,MPI_COMM_WORLD,ierr)
    end if
    if (leftpem /= MPI_PROC_NULL) then
        call MPI_RECV(prf(0,0,kstamg(n)-1),1, &
            plantypef,leftpem,taglr,MPI_COMM_WORLD,status,ierr)
    end if

    call MPI_TYPE_FREE(plantypef,ierr)

    return

end subroutine prolong

end module multigrid_module
