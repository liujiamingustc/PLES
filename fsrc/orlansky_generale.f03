!***********************************************************************
subroutine orlansky_generale(ktime)
   !***********************************************************************
   ! compute boundary conditions with orlansky
   !
   use myarrays2
   use myarrays_metri3
   use myarrays_velo3
   use mysending
   !
   use scala3
   use period
   use orl
   !
   use mpi

   implicit none

   !-----------------------------------------------------------------------
   !     array declaration
   integer i,j,k,ii,iii,ktime,isc
   integer ierr
   integer i_ob
      
   double precision c_orl ,amass,amass_loc
   double precision vol,vol_loc,c_orlansky(n2)

   real deltax
   !-----------------------------------------------------------------------
   i_ob = 0
   !-----------------------------------------------------------------------

   !     initialization
   do k=1,jz
      do j=1,jy
         du_dx1(j,k)=0.
         dv_dx1(j,k)=0.
         dw_dx1(j,k)=0.
        
         du_dx2(j,k)=0.
         dv_dx2(j,k)=0.
         dw_dx2(j,k)=0.
         do isc=1,nscal
            drho_dx1(isc,j,k)=0.
            drho_dx2(isc,j,k)=0.
         end do
      end do
   end do

   do k=1,jz
      do i=1,jx
         du_dy3(i,k)=0.
         dv_dy3(i,k)=0.
         dw_dy3(i,k)=0.

         du_dy4(i,k)=0.
         dv_dy4(i,k)=0.
         dw_dy4(i,k)=0.
         do isc=1,nscal
            drho_dy3(isc,i,k)=0.
            drho_dy4(isc,i,k)=0.
         end do
      end do
   end do

   do j=1,jy
      do i=1,jx
         du_dz5(i,j)=0.
         dv_dz5(i,j)=0.
         dw_dz5(i,j)=0.
        
         du_dz6(i,j)=0.
         dv_dz6(i,j)=0.
         dw_dz6(i,j)=0.
         do isc=1,nscal
            drho_dz5(isc,i,j)=0.
            drho_dz6(isc,i,j)=0.
         end do
      end do
   end do
      
      
   !-----------------------------------------------------------------------
   !     ORLANSKY
   !-----------------------------------------------------------------------
   if(i_ob == 1)then


      ! side 1 constant csi
      do iii=1,ip
         if(infout1.eq.1)then

            do k=kparasta,kparaend
               do j=1,jy
      
                  du_dx1(j,k)=u(1,j,k)+delu(1,j,k)
                  dv_dx1(j,k)=v(1,j,k)+delv(1,j,k)
                  dw_dx1(j,k)=w(1,j,k)+delw(1,j,k)

                  du_dx1(j,k)=index_out1(j,k)*du_dx1(j,k)
                  dv_dx1(j,k)=index_out1(j,k)*dv_dx1(j,k)
                  dw_dx1(j,k)=index_out1(j,k)*dw_dx1(j,k)
                  do isc=1,nscal
                     drho_dx1(isc,j,k)=rhov(isc,1,j,k)
                     drho_dx1(isc,j,k)=index_out1(j,k)*drho_dx1(isc,j,k)
                  enddo
               enddo
            enddo

         endif
         !
         !.......................................................................
         ! side 2 constant csi
         if(infout2.eq.1)then
      
      
      
      
            amass_loc = 0.
            amass = 0.
            vol_loc = 0.
            vol = 0.


            do j=1,jy
               do k=kparasta,kparaend
                  amass_loc = amass_loc + uc(jx,j,k)
                  vol_loc = vol_loc + giac(jx,j,k)
               end do
            end do

            call MPI_ALLREDUCE(amass_loc,amass,1,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,ierr)

            call MPI_ALLREDUCE(vol_loc,vol,1,MPI_DOUBLE_PRECISION,MPI_SUM,MPI_COMM_WORLD,ierr)



            !      c_orl = amass/( (z(1,1,jz)-z(1,1,0)) * (y(1,jy,1)-y(1,0,1))  )

            !      if(myid.eq.0)write(*,*)'C_ORL',c_orl
      

            do k=kparasta,kparaend
               do j=1,jy

                  !      c_orl=c_orlansky(j) !uc(jx,j,k)/giac(jx,j,k)
                  c_orl=uc(jx,j,k)/giac(jx,j,k)

                  if(c_orl.gt.0) then
                     du_dx2(j,k)=u(jx+1,j,k)-2.*dt*c_orl*(u(jx+1,j,k)-u(jx,j,k))
                     !     >                  /deltax
                     dv_dx2(j,k)=v(jx,j,k)    !v(jx+1,j,k)-2.*dt*c_orl*(v(jx+1,j,k)-v(jx,j,k))
                     !     >                  /deltax
                     dw_dx2(j,k)=w(jx,j,k)    !w(jx+1,j,k)-2.*dt*c_orl*(w(jx+1,j,k)-w(jx,j,k))
                  !     >                  /deltax
                  !      drho_dx2(j,k)=rho(jx+1,j,k)
                  !     >              -2.*dt*c_orl*(rho(jx+1,j,k)-rho(jx,j,k))
                  else
                     du_dx2(j,k)=u(jx+1,j,k)-2.*dt*c_orl*(u(jx,j,k)-u(jx+1,j,k))
                     !     >                  /deltax
                     dv_dx2(j,k)=v(jx+1,j,k)-2.*dt*c_orl*(v(jx,j,k)-v(jx+1,j,k))
                     !     >                  /deltax
                     dw_dx2(j,k)=w(jx+1,j,k)-2.*dt*c_orl*(w(jx,j,k)-w(jx+1,j,k))
                  !     >                  /deltax

                  !      drho_dx2(j,k)=rho(jx+1,j,k)
                  !     >              -2.*dt*c_orl*(rho(jx,j,k)-rho(jx+1,j,k))
                  end if

                  du_dx2(j,k)=index_out2(j,k)*du_dx2(j,k)
                  dv_dx2(j,k)=index_out2(j,k)*dv_dx2(j,k)
                  dw_dx2(j,k)=index_out2(j,k)*dw_dx2(j,k)


                  do isc=1,nscal
                     drho_dx2(isc,j,k)=rhov(isc,jx,j,k)
                     drho_dx2(isc,j,k)=index_out2(j,k)*drho_dx2(isc,j,k)
                  end do
               enddo
            enddo

         endif
      enddo !fine loop ii=1,ip
      !-----------------------------------------------------------------------
      ! side 3 constant eta
      do iii=1,jp
         if(infout3.eq.1)then

            do k=kparasta,kparaend
               do i=1,jx
            
                  du_dy3(i,k)=u(i,1,k)+delu(i,1,k)
                  dv_dy3(i,k)=v(i,1,k)+delv(i,1,k)
                  dw_dy3(i,k)=w(i,1,k)+delw(i,1,k)

                  du_dy3(i,k)=index_out3(i,k)*du_dy3(i,k)
                  dv_dy3(i,k)=index_out3(i,k)*dv_dy3(i,k)
                  dw_dy3(i,k)=index_out3(i,k)*dw_dy3(i,k)

                  do isc=1,nscal
                     drho_dy3(isc,i,k)=rhov(isc,i,1,k)
                     drho_dy3(isc,i,k)=index_out3(i,k)*drho_dy3(isc,i,k)
                  end do
               enddo
            enddo

         endif
         !.......................................................................
         ! side 4 constant eta
         if(infout4.eq.1)then

            do k=kparasta,kparaend
               do i=1,jx

                  du_dy4(i,k)=u(i,jy,k)+delu(i,jy,k)
                  dv_dy4(i,k)=v(i,jy,k)+delv(i,jy,k)
                  dw_dy4(i,k)=w(i,jy,k)+delw(i,jy,k)


                  du_dy4(i,k)=index_out4(i,k)*du_dy4(i,k)
                  dv_dy4(i,k)=index_out4(i,k)*dv_dy4(i,k)
                  dw_dy4(i,k)=index_out4(i,k)*dw_dy4(i,k)

                  do isc=1,nscal
                     drho_dy4(isc,i,k)=rhov(isc,i,jy,k)
                     drho_dy4(isc,i,k)=index_out4(i,k)*drho_dy4(isc,i,k)
                  end do
               enddo
            enddo

         endif
      enddo !end loop jj=1,jp
      !-----------------------------------------------------------------------
      ! side 5 constant zita
      do iii=1,kp

         if(myid.eq.0)then
            if(infout5.eq.1)then

               do j=1,jy
                  do i=1,jx
  
                     du_dz5(i,j)=u(i,j,1)+delu(i,j,1)
                     dv_dz5(i,j)=v(i,j,1)+delv(i,j,1)
                     dw_dz5(i,j)=w(i,j,1)+delw(i,j,1)

            
                     du_dz5(i,j)=index_out5(i,j)*du_dz5(i,j)
                     dv_dz5(i,j)=index_out5(i,j)*dv_dz5(i,j)
                     dw_dz5(i,j)=index_out5(i,j)*dw_dz5(i,j)

                     do isc=1,nscal
                        drho_dz5(isc,i,j)=rhov(isc,i,j,1)
                        drho_dz5(isc,i,j)=index_out5(i,j)*drho_dz5(isc,i,j)
                     end do
                  enddo
               enddo

            endif
         endif
         !.......................................................................
         ! side 6 constant zita
         if(myid.eq.nproc-1)then
            if(infout6.eq.1)then

               do j=1,jy
                  do i=1,jx

                     du_dz6(i,j)=u(i,j,jz)+delu(i,j,jz)
                     dv_dz6(i,j)=v(i,j,jz)+delv(i,j,jz)
                     dw_dz6(i,j)=w(i,j,jz)+delw(i,j,jz)

	 
                     du_dz6(i,j)=index_out6(i,j)*du_dz6(i,j)
                     dv_dz6(i,j)=index_out6(i,j)*dv_dz6(i,j)
                     dw_dz6(i,j)=index_out6(i,j)*dw_dz6(i,j)

                     do isc=1,nscal
                        drho_dz6(isc,i,j)=rhov(isc,i,j,jz)
                        drho_dz6(isc,i,j)=index_out6(i,j)*drho_dz6(isc,i,j)
                     end do
                  enddo
               enddo

            endif
         endif

      enddo !end loop kk=1,kp
      
      
   end if ! i_ob = 1
      
      
      
      
      
   !-----------------------------------------------------------------------
   !     FREE SLIP
   !-----------------------------------------------------------------------
   if(i_ob == 0)then

      ! side 1 constant csi
      do iii=1,ip
         if(infout1==1)then

            do k=kparasta,kparaend
               do j=1,jy
      
                  du_dx1(j,k)=u(1,j,k)+delu(1,j,k)
                  dv_dx1(j,k)=v(1,j,k)+delv(1,j,k)
                  dw_dx1(j,k)=w(1,j,k)+delw(1,j,k)

                  du_dx1(j,k)=index_out1(j,k)*du_dx1(j,k)
                  dv_dx1(j,k)=index_out1(j,k)*dv_dx1(j,k)
                  dw_dx1(j,k)=index_out1(j,k)*dw_dx1(j,k)
                  do isc=1,nscal
                     drho_dx1(isc,j,k)=rhov(isc,1,j,k)
                     drho_dx1(isc,j,k)=index_out1(j,k)*drho_dx1(isc,j,k)
                  enddo
               enddo
            enddo

         endif
         !
         !.......................................................................
         ! side 2 constant csi
         if(infout2==1)then

            do k=kparasta,kparaend
               do j=1,jy
       
                  du_dx2(j,k)=u(jx,j,k)+delu(jx,j,k)
                  dv_dx2(j,k)=v(jx,j,k)+delv(jx,j,k)
                  dw_dx2(j,k)=w(jx,j,k)+delw(jx,j,k)


                  du_dx2(j,k)=index_out2(j,k)*du_dx2(j,k)
                  dv_dx2(j,k)=index_out2(j,k)*dv_dx2(j,k)
                  dw_dx2(j,k)=index_out2(j,k)*dw_dx2(j,k)

                  do isc=1,nscal
                     drho_dx2(isc,j,k)=rhov(isc,jx,j,k)
                     drho_dx2(isc,j,k)=index_out2(j,k)*drho_dx2(isc,j,k)
                  end do

               enddo
            enddo

         endif
      enddo !fine loop ii=1,ip
      !-----------------------------------------------------------------------
      ! side 3 constant eta
      do iii=1,jp
         if(infout3==1)then

            do k=kparasta,kparaend
               do i=1,jx
            
                  du_dy3(i,k)=u(i,1,k)+delu(i,1,k)
                  dv_dy3(i,k)=v(i,1,k)+delv(i,1,k)
                  dw_dy3(i,k)=w(i,1,k)+delw(i,1,k)

                  du_dy3(i,k)=index_out3(i,k)*du_dy3(i,k)
                  dv_dy3(i,k)=index_out3(i,k)*dv_dy3(i,k)
                  dw_dy3(i,k)=index_out3(i,k)*dw_dy3(i,k)

                  do isc=1,nscal
                     drho_dy3(isc,i,k)=rhov(isc,i,1,k)
                     drho_dy3(isc,i,k)=index_out3(i,k)*drho_dy3(isc,i,k)
                  end do
               enddo
            enddo

         endif
         !.......................................................................
         ! side 4 constant eta
         if(infout4==1)then

            do k=kparasta,kparaend
               do i=1,jx

                  du_dy4(i,k)=u(i,jy,k)+delu(i,jy,k)
                  dv_dy4(i,k)=v(i,jy,k)+delv(i,jy,k)
                  dw_dy4(i,k)=w(i,jy,k)+delw(i,jy,k)


                  du_dy4(i,k)=index_out4(i,k)*du_dy4(i,k)
                  dv_dy4(i,k)=index_out4(i,k)*dv_dy4(i,k)
                  dw_dy4(i,k)=index_out4(i,k)*dw_dy4(i,k)

                  do isc=1,nscal
                     drho_dy4(isc,i,k)=rhov(isc,i,jy,k)
                     drho_dy4(isc,i,k)=index_out4(i,k)*drho_dy4(isc,i,k)
                  end do
               enddo
            enddo

         endif
      enddo !end loop jj=1,jp
      !-----------------------------------------------------------------------
      ! side 5 constant zita
      do iii=1,kp

         if(myid==0)then
            if(infout5==1)then

               do j=1,jy
                  do i=1,jx
  
                     du_dz5(i,j)=u(i,j,1)+delu(i,j,1)
                     dv_dz5(i,j)=v(i,j,1)+delv(i,j,1)
                     dw_dz5(i,j)=w(i,j,1)+delw(i,j,1)

            
                     du_dz5(i,j)=index_out5(i,j)*du_dz5(i,j)
                     dv_dz5(i,j)=index_out5(i,j)*dv_dz5(i,j)
                     dw_dz5(i,j)=index_out5(i,j)*dw_dz5(i,j)

                     do isc=1,nscal
                        drho_dz5(isc,i,j)=rhov(isc,i,j,1)
                        drho_dz5(isc,i,j)=index_out5(i,j)*drho_dz5(isc,i,j)
                     end do
                  enddo
               enddo

            endif
         endif
         !.......................................................................
         ! side 6 constant zita
         if(myid==nproc-1)then
            if(infout6==1)then

               do j=1,jy
                  do i=1,jx

                     du_dz6(i,j)=u(i,j,jz)+delu(i,j,jz)
                     dv_dz6(i,j)=v(i,j,jz)+delv(i,j,jz)
                     dw_dz6(i,j)=w(i,j,jz)+delw(i,j,jz)

	 
                     du_dz6(i,j)=index_out6(i,j)*du_dz6(i,j)
                     dv_dz6(i,j)=index_out6(i,j)*dv_dz6(i,j)
                     dw_dz6(i,j)=index_out6(i,j)*dw_dz6(i,j)

                     do isc=1,nscal
                        drho_dz6(isc,i,j)=rhov(isc,i,j,jz)
                        drho_dz6(isc,i,j)=index_out6(i,j)*drho_dz6(isc,i,j)
                     end do
                  enddo
               enddo

            endif
         endif

      enddo !end loop kk=1,kp



   end if !i_ob == 0

   return
end
